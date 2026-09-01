import 'package:flutter/material.dart';

import '../../../core/ui/feel.dart';
import '../../../core/theme/foe_theme.dart';
import '../../creatures/models/creature_instance.dart';
import '../../creatures/services/creatures_controller.dart';
import '../../creatures/widgets/creature_card.dart';
import '../../common/widgets/app_back_button.dart';
import '../../common/widgets/empty_monster_slot.dart';
import '../../common/widgets/filter_pills.dart';
import '../../common/widgets/monster_tile_grid.dart';
import '../../common/widgets/parchment_page.dart' show ParchmentHeader;
import '../data/building_definitions.dart';
import '../models/placed_building.dart';
import '../settlement_controller.dart';
import 'parchment_sheet.dart';
import 'scroll_paper.dart' show kActionGreen, kParchmentInk;

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
// So it is two views now. The default one answers the question you opened it
// with (who works here, how many seats are left); the roster only appears when
// you actually want to hire, and that is the view that gets the full sorted
// list. Same two actions as before, in the order you need them.
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

  /// Which of the two views is open. Local, not a route: hiring is a step
  /// inside this dialog, and pushing a page would put the map back on screen
  /// between two halves of one decision.
  bool _adding = false;

  /// Set while [_adding] when the roster was opened from a FILLED seat (user
  /// 2026-08-30: "+ Kacheln in der Anzahl der Plätze... Wenn ich auf ein
  /// bereits eingestelltes Monster klicke, dann kann ich es austauschen") —
  /// the tile itself is the trigger now, one per seat, instead of a single +
  /// button that only ever adds. A pick here REPLACES this monster instead of
  /// filling a fresh seat; null means an empty tile opened the roster, so a
  /// pick just fills the next open seat as before.
  String? _swapTargetId;

  /// The sort control's own state (user 2026-08-31: "brauche ich in diesem
  /// Menü eine Sortierfunktion"). Null key = the post's own default order
  /// (best stat first, or lowest level first for Training) — same field-
  /// picks-then-flips shape as the Management screen's own sort pills.
  String? _sortKey;
  late bool _sortDescending = !_training;

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
    return CreaturesController()
        .creatures
        .where((c) => !hereIds.contains(c.id))
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
    setState(() {
      _adding = false;
      _swapTargetId = null;
    });
  }

  /// "Remove from post" — vacates the seat the tapped tile stood for without
  /// picking a replacement. The only way to empty a seat now that there is no
  /// bare crew list with its own ✕ per row.
  Future<void> _removeSwapTarget() async {
    final outgoing = _swapTarget;
    if (outgoing == null) return;
    await _set(outgoing, false);
    if (!mounted) return;
    setState(() {
      _adding = false;
      _swapTargetId = null;
    });
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
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _adding ? _addView() : _crewView(),
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
    if (_adding) {
      final swapping = _swapTarget;
      if (swapping != null) return 'Swap ${swapping.displayName}';
      return _training ? 'Add · lowest level first' : 'Add';
    }
    return kBuildingDefs[widget.building.buildingTypeId]?.name ??
        widget.building.buildingTypeId;
  }

  /// The role this seat reads, plus the seat count — only in the crew view;
  /// the roster reads its own sort pill instead.
  Widget? get _sheetTrailing {
    if (_adding) return null;
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

  // ── View 1: who works here ────────────────────────────────
  // Was a list of the crew plus one "Add a monster" button below it (user
  // 2026-08-30: "einen Screen haben bei welchen '+ Kacheln' angezeigt werden
  // in der Anzahl der Plätze. Wenn ich auf ein bereits eingestelltes Monster
  // klicke, dann kann ich es austauschen") — now every seat gets its own
  // tile, filled ones ARE the monster, empty ones are a "+", and a tap on a
  // filled tile opens the roster to SWAP that seat instead of a separate
  // hire-only button.
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
          onTap: () => setState(() {
            _adding = true;
            _swapTargetId = c.id;
          }),
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

  /// A place waiting to be filled — a tap opens the roster the same way the
  /// old "Add a monster" button did.
  Widget _emptySlotTile() => EmptyMonsterSlot(
        label: 'Add',
        onTap: () => setState(() {
          _adding = true;
          _swapTargetId = null;
        }),
      );

  // ── View 2: hire, ranked by the stat this post reads ───────
  List<Widget> _addView() {
    final candidates = _candidates;
    final swapping = _swapTarget;
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            // The app's own back control (2026-08-31 audit) — this used to
            // draw a bespoke Icons.arrow_back at 20px, a third size/glyph
            // alongside AppBackButton's 22px arrow_back_ios_new and the
            // header band's own back arrow.
            AppBackButton(
              onTap: () => setState(() {
                _adding = false;
                _swapTargetId = null;
              }),
              color: _accent,
            ),
            // The sort function (user 2026-08-31: "brauche ich in diesem
            // Menü eine Sortierfunktion") — the roster is every monster you
            // own, and the post's own default order is not always the one
            // worth browsing by.
            Expanded(child: _sortPill()),
          ],
        ),
      ),
      // Only offered from a filled tile — an empty seat has nothing to
      // vacate, so this would just duplicate "back".
      if (swapping != null) ...[
        GestureDetector(
          onTap: _removeSwapTarget,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: ShapeDecoration(
              color: _takenInk.withValues(alpha: 0.12),
              shape: FoE.facet(radius: 8),
            ),
            alignment: Alignment.center,
            child: Text(
              'Remove from post',
              style: FoE.label(size: 12).copyWith(color: _takenInk),
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
      if (candidates.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Text('No other monsters.',
              style: FoE.dim(size: 12).copyWith(color: _inkSoft)),
        )
      else
        monsterTileGrid([for (final c in candidates) _candidateTile(c)]),
    ];
  }

  /// Exactly [_filledSlotTile]'s tile — the same [CreatureCard], the same
  /// stat readout — plus the one thing a crew tile never needs: whether
  /// picking this monster is a free hire or a TRANSFER out of another post.
  Widget _candidateTile(CreatureInstance c) {
    final creatures = CreaturesController();
    final away = creatures.isOnExpedition(c.id);
    final idle = c.isKo || creatures.isBreeding(c.id);
    final elsewhere = _postedElsewhere(c);
    // ALREADY EMPLOYED is the state that has to jump out (user 2026-07-26:
    // "besser markieren, dass das Monster bereits eingestellt ist an einem
    // anderen Ort") — taking this monster costs THAT building its worker.
    final taken = elsewhere != null && !away && !idle;
    final label = away
        ? '🎒 Away'
        : idle
            ? '💤 Unfit for work'
            : taken
                ? 'Works in $elsewhere'
                : null;
    return Stack(
      children: [
        CreatureCard(
          creature: c,
          vitalsLabel: _training ? 'Level' : _role.stat.label,
          vitalsValue: _training ? c.level : c.statValue(_role.stat),
          onTap: () => _swapTargetId == null ? _set(c, true) : _swapWith(c),
        ),
        if (label != null)
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
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FoE.label(size: 9).copyWith(color: Colors.white),
                ),
              ),
            ),
          ),
        // The honest icon (user 2026-07-26): a TRANSFER arrow in amber
        // instead of the green plus, because that is what the tap does.
        Positioned(
          right: 6,
          bottom: 6,
          child: IgnorePointer(
            child: Container(
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
          ),
        ),
      ],
    );
  }

}
