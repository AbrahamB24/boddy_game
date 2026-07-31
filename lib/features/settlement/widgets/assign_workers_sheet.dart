import 'package:flutter/material.dart';

import '../../../core/ui/feel.dart';
import '../../../core/theme/foe_theme.dart';
import '../../creatures/models/creature_instance.dart';
import '../../creatures/services/creatures_controller.dart';
import '../../creatures/widgets/creature_sprite.dart';
import '../data/building_definitions.dart';
import '../models/placed_building.dart';
import '../settlement_controller.dart';
import 'meander_strip.dart';
import 'scroll_paper.dart'
    show
        kActionGreen,
        kParchmentInk,
        kParchmentLight,
        kParchmentMid,
        parchmentButton,
        parchmentButtonInk;

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
  static const Color _ink = kParchmentInk;
  static final Color _inkSoft = kParchmentInk.withValues(alpha: 0.78);
  static final Color _inkFaint = kParchmentInk.withValues(alpha: 0.55);
  static const Color _accent = FoE.gold;
  static final Color _ornament = kParchmentInk.withValues(alpha: 0.22);

  /// The "already employed somewhere else" mark. A rust/amber that is neither
  /// the green of a free hire nor the red of an error — this is a MOVE, and it
  /// costs another building its worker. Worn by the badge and by the transfer
  /// button, which is all the marking there is now that rows have no box.
  static const Color _takenInk = Color(0xFFB4661B);

  /// Which of the two views is open. Local, not a route: hiring is a step
  /// inside this dialog, and pushing a page would put the map back on screen
  /// between two halves of one decision.
  bool _adding = false;

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
    ..sort((x, y) => _rank(x).compareTo(_rank(y)));

  /// Everyone else, best first.
  ///
  /// A TRAINING post ranks lowest LEVEL first instead: every trainee earns the
  /// same XP/h, and against the 6·L^2.5 curve that hour is worth most to the
  /// least-levelled monster.
  List<CreatureInstance> get _candidates {
    final hereIds = _posted.map((c) => c.id).toSet();
    return CreaturesController()
        .creatures
        .where((c) => !hereIds.contains(c.id))
        .toList()
      ..sort((x, y) => _rank(x).compareTo(_rank(y)));
  }

  /// Sort key — smaller is better, so one comparator serves both orders.
  int _rank(CreatureInstance c) =>
      _training ? c.level : -c.statValue(_role.stat);

  /// The number this post is judged on.
  String _score(CreatureInstance c) =>
      _training ? 'Lv ${c.level}' : '${c.statValue(_role.stat)}';

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
    final messenger = ScaffoldMessenger.of(context);
    final err = post
        ? await widget.ctrl
            .assignCreatureToWorkshop(c.id, widget.building.id, _role.stat)
        : await widget.ctrl.assignCreatureToWorkshop(c.id, null, null);
    if (!mounted) return;
    if (err != null) {
      Feel.deny();
      messenger.showSnackBar(
        SnackBar(content: Text(err), backgroundColor: FoE.danger),
      );
      return;
    }
    // Hiring and letting go are both decisions that land — the sheet redraws
    // silently otherwise, and a mis-tap on a crowded roster felt identical to a
    // deliberate one.
    Feel.success();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds on every assignment: both lists are derived from the live
    // collection, so posting someone moves them between the two views.
    return AnimatedBuilder(
      animation: widget.ctrl,
      builder: (context, _) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 340,
          constraints: const BoxConstraints(maxHeight: 520),
          // The SAME parchment surface and meander ornament as the building
          // dialog (user 2026-07-26: "optisch an das andere Pop Up anpassen").
          // This sheet is opened FROM that dialog and edits what it shows —
          // a dark panel over a parchment one read as a different app.
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [kParchmentLight, kParchmentMid],
            ),
          ),
          child: Stack(
            children: [
              // Wallpaper first, so it can never land over a line of text.
              Positioned(
                left: 12,
                top: 0,
                bottom: 0,
                width: 14,
                child: MeanderStrip(color: _ornament),
              ),
              Positioned(
                right: 12,
                top: 0,
                bottom: 0,
                width: 14,
                child: MeanderStrip(color: _ornament, flip: true),
              ),
              Padding(
                // Wide sides: the meander bands live in that margin.
                padding: const EdgeInsets.fromLTRB(34, 16, 34, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _adding ? _addView() : _crewView(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── View 1: who works here ────────────────────────────────
  List<Widget> _crewView() {
    final posted = _posted;
    final free = _slots - posted.length;
    return [
      _header(
        _training ? 'Training' : _role.stat.label,
        // The seat count IS the headline: it decides whether the + button
        // below is even offered.
        '${posted.length} / $_slots',
        full: free <= 0,
      ),
      const SizedBox(height: 10),
      Flexible(
        child: posted.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  'Nobody works here.\nThis building produces nothing.',
                  style: FoE.dim(size: 12).copyWith(color: FoE.danger),
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [for (final c in posted) _crewRow(c)],
              ),
      ),
      const SizedBox(height: 12),
      if (free > 0)
        _bigButton(
          label: 'Add a monster',
          sub: '$free ${free == 1 ? 'seat' : 'seats'} free',
          gold: true,
          onTap: () => setState(() => _adding = true),
        )
      else
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          child: Text('Every seat taken',
              style: FoE.dim(size: 11).copyWith(color: _inkFaint)),
        ),
      const SizedBox(height: 8),
      _bigButton(label: 'Close', onTap: () => Navigator.pop(context)),
    ];
  }

  Widget _crewRow(CreatureInstance c) {
    final creatures = CreaturesController();
    final away = creatures.isOnExpedition(c.id);
    final idle = c.isKo || creatures.isBreeding(c.id);
    return _row(
      c: c,
      // A posted monster that isn't actually in the building is the one thing
      // this list must not hide: the post looks staffed and yields nothing.
      note: away
          ? '🎒 Away — seat held, no output'
          : idle
              ? '💤 Unfit for work — no output'
              : null,
      noteColor: away || idle ? _accent : null,
      trailing: const Icon(Icons.remove_circle_outline,
          size: 20, color: FoE.danger),
      onTap: () => _set(c, false),
    );
  }

  // ── View 2: hire, ranked by the stat this post reads ───────
  List<Widget> _addView() {
    final candidates = _candidates;
    return [
      Row(
        children: [
          GestureDetector(
            onTap: () => setState(() => _adding = false),
            child: const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.arrow_back, size: 18, color: _accent),
            ),
          ),
          Expanded(
            child: Text(
              _training ? 'Add · lowest level first' : 'Add',
              style: FoE.title(size: 15).copyWith(color: _ink),
            ),
          ),
        ],
      ),
      Text(
        _training
            ? 'An hour of training is worth most to the lowest level.'
            : 'Ranked by ${_role.stat.label} — best first.',
        style: FoE.dim(size: 10).copyWith(color: _inkSoft),
      ),
      const SizedBox(height: 10),
      Flexible(
        child: candidates.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Text('No other monsters.',
                    style: FoE.dim(size: 12).copyWith(color: _inkSoft)),
              )
            : ListView(
                shrinkWrap: true,
                children: [for (final c in candidates) _candidateRow(c)],
              ),
      ),
      const SizedBox(height: 12),
      _bigButton(
        label: 'Done',
        onTap: () => setState(() => _adding = false),
      ),
    ];
  }

  Widget _candidateRow(CreatureInstance c) {
    final creatures = CreaturesController();
    final away = creatures.isOnExpedition(c.id);
    final idle = c.isKo || creatures.isBreeding(c.id);
    final elsewhere = _postedElsewhere(c);
    // ALREADY EMPLOYED is the state that has to jump out (user 2026-07-26:
    // "besser markieren, dass das Monster bereits eingestellt ist an einem
    // anderen Ort"). A faint border and a caption did not: it looked like any
    // other free monster, one tap from quietly gutting another building.
    //
    // So it stops wearing the "hire" costume entirely: warm wash, solid border,
    // a badge naming the building, and — the honest part — a TRANSFER arrow in
    // amber instead of the green plus, because that is what the tap does.
    final taken = elsewhere != null && !away && !idle;
    return _row(
      c: c,
      // Priority: away/K.O. first (it can't work at all), then the posting it
      // would be taken from.
      note: away
          ? '🎒 Away'
          : idle
              ? '💤 Unfit for work'
              : null,
      noteColor: _accent,
      badge: taken ? elsewhere : null,
      trailing: Container(
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
      onTap: () => _set(c, true),
    );
  }

  // ── Shared bits ───────────────────────────────────────────
  /// Title on the left, the seat count on the right — BARE (user 2026-07-26:
  /// "n/n ohne hintergrund/Box"). On paper a boxed number reads as a button;
  /// the count is a readout, and a full post says so by going accent-coloured.
  Widget _header(String title, String count, {required bool full}) => Row(
    children: [
      Expanded(
        child: Text(title, style: FoE.title(size: 15).copyWith(color: _ink)),
      ),
      const SizedBox(width: 8),
      Text(
        count,
        style: FoE.value(size: 13).copyWith(color: full ? _accent : _ink),
      ),
    ],
  );

  /// One monster: its SPRITE, its name, the number this post judges it on, and
  /// the action.
  ///
  /// No box (user 2026-07-26: "box entfernen, dafür das Icon des Monsters
  /// hinzufügen") — on parchment a bordered row per monster made a short list
  /// look like a form to fill in, and the sprite tells you who this is faster
  /// than any frame around the name.
  ///
  /// [badge] is what carries the "already employed" mark now that there is no
  /// row colour to carry it: a filled chip naming the building this monster
  /// would be taken FROM. A plain caption was too quiet for a tap that empties
  /// a post somewhere else on the map.
  Widget _row({
    required CreatureInstance c,
    required String? note,
    required Color? noteColor,
    required Widget trailing,
    required VoidCallback onTap,
    String? badge,
  }) =>
      GestureDetector(
        // Opaque: without a filled box the row is mostly transparent, and
        // deferToChild would drop every tap that misses the text.
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: c.imageUrl == null
                    ? Icon(Icons.pets, size: 18, color: _accent)
                    : CreatureSprite(
                        url: c.imageUrl!,
                        fallback: Icon(Icons.pets, size: 18, color: _accent),
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.displayName,
                      style: FoE.label(size: 13).copyWith(color: _ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (badge != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: ShapeDecoration(color: _takenInk, shape: FoE.facet(radius: 4)),
                          child: Text(
                            'Works in $badge',
                            style: FoE.label(size: 9)
                                .copyWith(color: Colors.white),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    if (note != null)
                      Text(
                        note,
                        style: FoE.dim(size: 9)
                            .copyWith(color: noteColor ?? _inkFaint),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _score(c),
                style: FoE.value(size: 13).copyWith(color: _accent),
              ),
              const SizedBox(width: 8),
              trailing,
            ],
          ),
        ),
      );

  /// The building dialog's Upgrade button, to the pixel (user 2026-07-26:
  /// "monster hinzufügen bitte genau gleich gestalten") — same pill, same
  /// vertical padding, same 13pt label over a 10pt sub-line. The count lives on
  /// that second line, exactly where Upgrade puts its cost and build time,
  /// instead of being packed into the label.
  Widget _bigButton({
    required String label,
    String? sub,
    bool gold = false,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: parchmentButton(active: gold),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FoE.label(size: 13)
                    .copyWith(color: parchmentButtonInk(active: gold)),
              ),
              if (sub != null) ...[
                const SizedBox(height: 3),
                Text(
                  sub,
                  textAlign: TextAlign.center,
                  style: FoE.dim(size: 10)
                      .copyWith(color: parchmentButtonInk(active: gold)),
                ),
              ],
            ],
          ),
        ),
      );
}
