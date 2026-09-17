import 'package:flutter/material.dart';

import '../../../core/ui/feel.dart';
import '../../../core/theme/foe_theme.dart';
import '../../creatures/models/creature_enums.dart';
import '../../creatures/models/creature_instance.dart';
import '../../creatures/services/creatures_controller.dart';
import '../../creatures/widgets/creature_card.dart';
import '../../creatures/widgets/creature_sprite.dart';
import '../../common/widgets/empty_monster_slot.dart';
import '../../common/widgets/filter_pills.dart';
import '../../common/widgets/monster_tile_grid.dart';
import '../../common/widgets/parchment_kit.dart' show ParchmentSectionHeader;
import '../../common/widgets/parchment_page.dart' show ParchmentHeader;
import '../data/building_definitions.dart';
import '../models/placed_building.dart';
import '../settlement_controller.dart';
import 'parchment_sheet.dart';
import 'scroll_paper.dart' show kActionGreen, kParchmentInk;
import '../../../core/ui/pressable.dart';

// ── Posting monsters to a work post (user 2026-07-26) ───────────────────────
// "mache dieses pop up menü neu und übersichtlicher. Ich brauche sicher eine
// Anzeige, welche bereits hier arbeiten und einen Plus Button um hinzuzufügen.
// Die Monster werden dann nach ihrem entsprechenden Stat geordnet angezeigt,
// wobei diese, welche am Arbeiten sind an einem anderen Ort speziell markiert
// werden."
//
// The old sheet was ONE list of every monster you own, with whoever worked here
// floated to the top and no visual break between the two groups. Reading "who
// is in this building" meant counting gold borders down a list of forty, and
// the two jobs it does — reviewing the crew, and hiring — fought for the same
// space.
//
// That became two views (2026-08-30): a crew grid up top, a full roster
// behind an "Add" tap. Better, but user 2026-09-06: "sehe ich aktuell noch zu
// wenig, welche Monster aktuell im Gebäude arbeiten, welche frei sind, welche
// anderso arbeiten und welchen Stat sie haben" — free/away/elsewhere status
// only showed up after leaving the crew screen. One continuous list now: the
// crew grid stays up top, and the roster (dense rows, not tiles, so more of
// it reads at once) sits right under it, always visible.
class AssignWorkersSheet extends StatefulWidget {
  final SettlementController ctrl;
  final PlacedBuilding building;
  final WorkshopRole role;

  const AssignWorkersSheet({
    super.key,
    required this.ctrl,
    required this.building,
    required this.role,
  });

  @override
  State<AssignWorkersSheet> createState() => _AssignWorkersSheetState();
}

class _AssignWorkersSheetState extends State<AssignWorkersSheet> {
  // ── Ink on parchment ──
  // The dark FoE palette is invisible on this surface, so every colour here is
  // the building dialog's: one brown ink at three strengths, plus the accent it
  // uses for labels.
  static final Color _inkSoft = kParchmentInk.withValues(alpha: 0.78);
  static const Color _accent = FoE.gold;

  /// The "already employed somewhere else" mark. A rust/amber that is neither
  /// the green of a free hire nor the red of an error — this is a MOVE, and it
  /// costs another building its worker. Worn by the badge and by the transfer
  /// button, which is all the marking there is now that rows have no box.
  static const Color _takenInk = Color(0xFFB4661B);

  /// Set when a FILLED seat's tile was tapped (user 2026-08-30: "+ Kacheln in
  /// der Anzahl der Plätze... Wenn ich auf ein bereits eingestelltes Monster
  /// klicke, dann kann ich es austauschen") — the tile itself is the trigger,
  /// one per seat, instead of a single + button that only ever adds. A pick
  /// made while this is set REPLACES this monster instead of filling a fresh
  /// seat; null means the next pick just fills the next open seat.
  ///
  /// ONE CONTINUOUS LIST now, not two views to switch between (user
  /// 2026-09-06: "sehe ich aktuell noch zu wenig, welche Monster aktuell im
  /// Gebäude arbeiten, welche frei sind, welche anderso arbeiten und welchen
  /// Stat sie haben") — the roster used to be its own screen behind an "Add"
  /// tap, so free/away/elsewhere status and the readable stat only showed up
  /// after leaving the crew view. It is always on screen below the crew now;
  /// this field only tracks whether tapping a roster row HIRES or SWAPS.
  String? _swapTargetId;

  /// The sort control's own state (user 2026-08-31: "brauche ich in diesem
  /// Menü eine Sortierfunktion"). Null key = the post's own default order
  /// (best stat first, or lowest level first for Training) — same field-
  /// picks-then-flips shape as the Management screen's own sort pills.
  String? _sortKey;
  late bool _sortDescending = !_training;

  /// Search + filter, added alongside the roster's existing sort (user
  /// 2026-09-11: "überall, wo ich ein Monster oder eine Gruppe auswähle,
  /// sollen diese ... eine Sortier, Filter- und Suchfunktion haben"). Only
  /// the "everyone else" roster is filtered — the crew grid above it is one
  /// tile per seat this post HAS, not a browsable list.
  final _search = TextEditingController();
  String _query = '';
  CreatureElement? _filterElement;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  CreatureInstance? get _swapTarget {
    final id = _swapTargetId;
    if (id == null) return null;
    for (final c in CreaturesController().creatures) {
      if (c.id == id) return c;
    }
    return null;
  }

  WorkshopRole get _role => widget.role;
  bool get _training => _role.resource == WorkshopRole.kTraining;
  int get _slots => effectiveSlots(_role, widget.building.level);

  /// Everyone posted to THIS building on THIS role.
  List<CreatureInstance> get _posted => CreaturesController()
      .creatures
      .where((c) =>
          c.assignedBuildingId == widget.building.id &&
          c.assignedStat == _role.stat)
      .toList()
    ..sort(_cmp);

  /// Everyone else, best first — PLUS the seat's own current occupant when
  /// this roster was opened to swap it (user 2026-08-30: "sollen mir alle
  /// verfügbaren Monster angezeigt werden, inkl. dem abgewählten") — the tap
  /// that opened this view already took that monster off the seat in the
  /// UI's own eyes, but it is still a real, pickable option, not a stranger
  /// to hide.
  ///
  /// A TRAINING post ranks lowest LEVEL first instead: every trainee earns the
  /// same XP/h, and against the 6·L^2.5 curve that hour is worth most to the
  /// least-levelled monster.
  List<CreatureInstance> get _candidates {
    final hereIds = _posted.map((c) => c.id).toSet()..remove(_swapTargetId);
    final q = _query.trim().toLowerCase();
    return CreaturesController()
        .creatures
        .where((c) =>
            !hereIds.contains(c.id) &&
            (_filterElement == null || c.species?.element == _filterElement) &&
            (q.isEmpty || c.displayName.toLowerCase().contains(q)))
        .toList()
      ..sort(_cmp);
  }

  /// The sort pill's own comparator. A null [_sortKey] is the post's default
  /// order (best stat first, or lowest level first for Training); picking a
  /// field explicitly always starts descending, the same convention the
  /// Management screen's sort pills use, then flips on a second tap.
  int _cmp(CreatureInstance x, CreatureInstance y) {
    final cmp = switch (_sortKey) {
      'level' => x.level.compareTo(y.level),
      'name' => x.displayName.compareTo(y.displayName),
      _ => _training
          ? x.level.compareTo(y.level)
          : x.statValue(_role.stat).compareTo(y.statValue(_role.stat)),
    };
    return _sortDescending ? -cmp : cmp;
  }

  /// The building a monster is posted to, when it is NOT this one — the mark
  /// the user asked for. Naming the building beats a bare "elsewhere": taking
  /// this monster costs THAT building its output, and you can only weigh that
  /// if you know which one it is.
  String? _postedElsewhere(CreatureInstance c) {
    final id = c.assignedBuildingId;
    if (id == null || id == widget.building.id) return null;
    for (final b in widget.ctrl.buildings) {
      if (b.id == id) return kBuildingDefs[b.buildingTypeId]?.name ?? b.id;
    }
    return null;
  }

  Future<void> _set(CreatureInstance c, bool post) async {
    final err = post
        ? await widget.ctrl
            .assignCreatureToWorkshop(c.id, widget.building.id, _role.stat)
        : await widget.ctrl.assignCreatureToWorkshop(c.id, null, null);
    if (!mounted) return;
    if (err != null) {
      // The buzz alone now (user 2026-08-29: "wirklich alle pop up
      // nachrichten... löschen") — no pop-up explaining why.
      Feel.deny();
      return;
    }
    // Hiring and letting go are both decisions that land — the sheet redraws
    // silently otherwise, and a mis-tap on a crowded roster felt identical to a
    // deliberate one.
    Feel.success();
  }

  /// A pick made while [_swapTargetId] is set: the outgoing monster is freed
  /// FIRST — the seat is already full, so posting the new one before that
  /// would just bounce off the same capacity check hiring into a full post
  /// does.
  Future<void> _swapWith(CreatureInstance candidate) async {
    final outgoing = _swapTarget;
    if (outgoing != null) await _set(outgoing, false);
    await _set(candidate, true);
    if (!mounted) return;
    setState(() => _swapTargetId = null);
  }

  /// "Remove from post" — vacates the seat the tapped tile stood for without
  /// picking a replacement. The only way to empty a seat now that there is no
  /// bare crew list with its own ✕ per row.
  Future<void> _removeSwapTarget() async {
    final outgoing = _swapTarget;
    if (outgoing == null) return;
    await _set(outgoing, false);
    if (!mounted) return;
    setState(() => _swapTargetId = null);
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds on every assignment: both lists are derived from the live
    // collection, so posting someone moves them between the two views.
    //
    // A bottom sheet now, not a centred dialog (user 2026-08-30: "einen
    // Screen…, welcher von unten kommt" — pointing at the daily-tasks sheet)
    // — [ParchmentSheet] is the same surface "the worker picker" already
    // names itself after in its own doc comment, just never wired up here.
    // Full sheet width also fixes the tiles being smaller than everywhere
    // else (user, same message: "die Kacheln sollen genau so gross sein wie
    // andernorts") — they were shrunk to fit the old dialog's fixed 340px.
    return AnimatedBuilder(
      animation: widget.ctrl,
      builder: (context, _) => ParchmentSheet(
        title: _sheetTitle,
        trailing: _sheetTrailing,
        builder: (context, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          // kMonsterTilePageMargin (24), not 36 (+16/+16, 2026-09-06:
          // ParchmentSheet's own bands widened from flush-to-edge to a 14px
          // inset/16px wide band) — the crew grid above is a
          // [monsterTileGrid], which sizes tiles off the raw device width
          // assuming a 24px host margin, same as the Monsters screen (user
          // 2026-09-11: "bitte 3 Boxen nebeneinander und nicht nur 2",
          // caught on the hunt group picker but the same mismatch here).
          // The roster rows below it are full-width regardless, so this
          // only costs them 12px of extra breathing room, not a layout bug.
          padding: const EdgeInsets.fromLTRB(kMonsterTilePageMargin, 14, kMonsterTilePageMargin, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [..._crewView(), ..._rosterSection()],
          ),
        ),
      ),
    );
  }

  /// The sheet's own header band names the view — no more duplicate title
  /// printed again inside the content below it.
  ///
  /// WHICH BUILDING, not which stat (user 2026-08-31: "der Titel soll nicht
  /// der entsprechende Stat sein, sondern der Name des Gebäudes") — a sheet
  /// full of monster tiles already says "assignment"; what it did not say
  /// was which of your buildings you were staffing. The stat/role itself
  /// moved to [_sheetTrailing], beside the seat count, so it is not lost.
  String get _sheetTitle {
    final swapping = _swapTarget;
    if (swapping != null) return 'Swap ${swapping.displayName}';
    return kBuildingDefs[widget.building.buildingTypeId]?.name ??
        widget.building.buildingTypeId;
  }

  /// The role this seat reads, plus the seat count.
  Widget? get _sheetTrailing {
    final free = _slots - _posted.length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _training ? 'Training' : _role.stat.label,
          style: FoE.dim(size: 11).copyWith(color: _inkSoft),
        ),
        const SizedBox(width: 6),
        Text(
          '${_posted.length} / $_slots',
          style: ParchmentHeader.titleStyle(size: 13).copyWith(
            color: free <= 0 ? _accent : ParchmentHeader.engravedInk,
          ),
        ),
      ],
    );
  }

  // ── The crew: who works here ────────────────────────────────
  // Was a list of the crew plus one "Add a monster" button below it (user
  // 2026-08-30: "einen Screen haben bei welchen '+ Kacheln' angezeigt werden
  // in der Anzahl der Plätze. Wenn ich auf ein bereits eingestelltes Monster
  // klicke, dann kann ich es austauschen") — every seat gets its own tile,
  // filled ones ARE the monster, empty ones are a "+", and a tap on a filled
  // tile sets it as the roster's SWAP target instead of a separate hire-only
  // button.
  List<Widget> _crewView() {
    final posted = _posted;
    return [
      if (posted.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'Nobody works here.\nThis building produces nothing.',
            style: FoE.dim(size: 12).copyWith(color: FoE.danger),
          ),
        ),
      _slotsGrid(posted),
    ];
  }

  /// One tile per seat this post HAS — not per free seat, so the whole crew
  /// is visible at a glance instead of counted against a headline number.
  /// The shared [monsterTileGrid] size (user 2026-08-31: "sollen immer genau
  /// gleich hoch sein, überall in der gesamten App") — not this sheet's own
  /// copy of the sizing maths any more.
  Widget _slotsGrid(List<CreatureInstance> posted) => monsterTileGrid([
        for (var i = 0; i < _slots; i++)
          i < posted.length ? _filledSlotTile(posted[i]) : _emptySlotTile(),
      ]);

  /// A tap opens the roster in SWAP mode for this exact monster — the tile
  /// itself is now the only entry point, filling the role the ✕ and the
  /// crew-list row used to split between them.
  ///
  /// The card's top-right readout is overridden with THIS post's stat (user
  /// 2026-08-30: "wobei der entsprechende Wert prominent gezeigt werden
  /// soll") — power is not what decides who belongs in this seat.
  Widget _filledSlotTile(CreatureInstance c) {
    final creatures = CreaturesController();
    final away = creatures.isOnExpedition(c.id);
    final breeding = creatures.isBreeding(c.id);
    return Stack(
      children: [
        CreatureCard(
          creature: c,
          vitalsLabel: _training ? 'Level' : _role.stat.label,
          vitalsValue: _training ? c.level : c.statValue(_role.stat),
          onTap: () => setState(() => _swapTargetId = c.id),
        ),
        // A posted monster that isn't actually IN the building is the one
        // thing this tile must not hide: the post looks staffed and yields
        // nothing. K.O. already shows on the card itself; away/breeding
        // don't, so they get their own mark.
        if (away || breeding)
          Positioned(
            left: 6,
            top: 6,
            child: IgnorePointer(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: ShapeDecoration(
                  color: _takenInk,
                  shape: FoE.facet(radius: 6),
                ),
                child: Text(
                  away ? '🎒 no output' : '💤 no output',
                  style: FoE.label(size: 9).copyWith(color: Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// The roster's sort control — same field-picks-then-flips pill the
  /// Management screen's Work tab uses, on the parchment palette this sheet
  /// stands on.
  Widget _sortPill() {
    final defaultLabel = _training ? 'Level' : _role.stat.label;
    return MenuPill<String>(
      palette: PillPalette.parchment,
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
        // Training's default IS level, so a separate 'level' entry would
        // just repeat the first one under a different key.
        if (!_training) const MapEntry('level', 'Level'),
        const MapEntry('name', 'Name'),
      ],
      trailing: Icon(
        _sortDescending ? Icons.arrow_downward : Icons.arrow_upward,
        size: 14,
        color: _accent,
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

  Widget _searchPill() => SearchPill(
    controller: _search,
    palette: PillPalette.parchment,
    onChanged: (v) => setState(() => _query = v),
  );

  Widget _filterPill() => MenuPill<String>(
    palette: PillPalette.parchment,
    icon: Icons.filter_alt_outlined,
    label: _filterElement?.label ?? 'Every type',
    engaged: _filterElement != null,
    value: _filterElement?.name ?? '',
    entries: [
      const MapEntry('', 'Every type'),
      for (final e in CreatureElement.values)
        if (e != CreatureElement.neutral) MapEntry(e.name, '${e.emoji} ${e.label}'),
    ],
    onSelected: (v) => setState(
      () => _filterElement = v.isEmpty ? null : CreatureElement.fromName(v),
    ),
  );

  /// A place waiting to be filled. The roster below is always on screen now
  /// (user 2026-09-06), so a tap here just clears any pending swap — the
  /// tile still looks and reads exactly like a filled seat's, tap included.
  Widget _emptySlotTile() => EmptyMonsterSlot(
        label: 'Add',
        onTap: () => setState(() => _swapTargetId = null),
      );

  // ── The roster: everyone else, always on screen ────────────
  // Used to be its own view behind an "Add" tap (user 2026-09-06: "sehe ich
  // aktuell noch zu wenig, welche Monster aktuell im Gebäude arbeiten, welche
  // frei sind, welche anderso arbeiten und welchen Stat sie haben") — reading
  // free/away/elsewhere status meant leaving the crew screen first. It sits
  // right under the crew grid now, dense ROWS rather than a tile grid so more
  // of the roster's status/stat reads at once without scrolling.
  List<Widget> _rosterSection() {
    final candidates = _candidates;
    final swapping = _swapTarget;
    return [
      const SizedBox(height: 14),
      ParchmentSectionHeader(
        title: 'Everyone else',
        // Flexible, not the bare pill (2026-09-06 crash fix) —
        // [ParchmentSectionHeader]'s Row hands `trailing` unbounded width
        // (fine for its usual small ⓘ button), but [MenuPill] has its OWN
        // Expanded child inside and needs a BOUNDED width from somewhere;
        // wrapping it here is what used to come for free from the old
        // `Expanded(child: _sortPill())` Row this replaced.
        trailing: Flexible(child: _sortPill()),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(flex: 3, child: _searchPill()),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: _filterPill()),
        ],
      ),
      const SizedBox(height: 6),
      // Only offered once a filled tile is tapped — an empty seat has
      // nothing to vacate.
      if (swapping != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Swapping ${swapping.displayName}',
                  style: FoE.dim(size: 11).copyWith(color: _inkSoft),
                ),
              ),
              Pressable(
                onTap: _removeSwapTarget,
                child: Text(
                  'Remove from post',
                  style: FoE.label(size: 11).copyWith(color: _takenInk),
                ),
              ),
              const SizedBox(width: 10),
              Pressable(
                onTap: () => setState(() => _swapTargetId = null),
                child: Icon(Icons.close, size: 16, color: _inkSoft),
              ),
            ],
          ),
        ),
      if (candidates.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Text('No other monsters.',
              style: FoE.dim(size: 12).copyWith(color: _inkSoft)),
        )
      else
        for (final c in candidates) _rosterRow(c),
    ];
  }

  /// One roster row: a thumbnail, the name, the stat THIS post reads (bold —
  /// that number is the whole reason to sort the list), a status badge when
  /// it isn't a free hire, and the same honest add/transfer icon the old
  /// tile grid used.
  Widget _rosterRow(CreatureInstance c) {
    final creatures = CreaturesController();
    final away = creatures.isOnExpedition(c.id);
    final idle = c.isKo || creatures.isBreeding(c.id);
    final elsewhere = _postedElsewhere(c);
    // ALREADY EMPLOYED is the state that has to jump out (user 2026-07-26:
    // "besser markieren, dass das Monster bereits eingestellt ist an einem
    // anderen Ort") — taking this monster costs THAT building its worker.
    final taken = elsewhere != null && !away && !idle;
    final status = away
        ? '🎒 Away'
        : idle
            ? '💤 Unfit'
            : taken
                ? 'Works in $elsewhere'
                : null;
    final statValue = _training ? c.level : c.statValue(_role.stat);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Pressable(
        behavior: HitTestBehavior.opaque,
        onTap: () => _swapTargetId == null ? _set(c, true) : _swapWith(c),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: ParchmentSheet.card,
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: (c.imageUrl ?? '').isEmpty
                    ? Container(
                        width: 36,
                        height: 36,
                        color: _inkSoft.withValues(alpha: 0.15),
                        child: Icon(Icons.pets, size: 18, color: _inkSoft),
                      )
                    : CreatureSprite(
                        url: c.imageUrl!,
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                        fallback: Container(
                          width: 36,
                          height: 36,
                          color: _inkSoft.withValues(alpha: 0.15),
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  c.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FoE.label(size: 13).copyWith(color: ParchmentSheet.ink),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$statValue',
                style: FoE.value(size: 14).copyWith(color: _accent),
              ),
              if (status != null) ...[
                const SizedBox(width: 8),
                Container(
                  constraints: const BoxConstraints(maxWidth: 96),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: ShapeDecoration(
                    color: _takenInk,
                    shape: FoE.facet(radius: 6),
                  ),
                  child: Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FoE.label(size: 9).copyWith(color: Colors.white),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              // The honest icon (user 2026-07-26): a TRANSFER arrow in amber
              // instead of the green plus, because that is what the tap does.
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: taken ? _takenInk : kActionGreen,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  taken ? Icons.swap_horiz : Icons.add,
                  size: 15,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
