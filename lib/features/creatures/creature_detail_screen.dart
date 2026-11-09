import 'package:flutter/material.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/foe_theme.dart';
import '../../core/theme/cream_kit.dart';
import '../../core/theme/voxel_kit.dart';
import '../../core/ui/feel.dart';
import '../../core/ui/snack.dart';
import '../settlement/data/building_definitions.dart';
import '../settlement/data/item_definitions.dart';
import '../settlement/services/crafting.dart';
import '../settlement/widgets/building_icon.dart';
import '../settlement/settlement_controller.dart';
import 'models/ability_def.dart';
import 'models/creature_enums.dart';
import 'models/creature_instance.dart';
import 'models/species_def.dart';
import 'services/combat_engine.dart';
import 'combat_school_screen.dart';
import 'widgets/creature_backdrop.dart';
import 'widgets/creature_family.dart' show CreatureFigure;
import 'widgets/creature_sprite.dart';
import 'widgets/monster_sheet.dart' show MonsterSheets;
import 'services/creature_power.dart';
import 'services/creatures_controller.dart';
import '../common/widgets/recess_bar.dart';
import '../../core/ui/pressable.dart';
import '../../core/theme/voxel_icons.dart';
import '../../core/ui/game_text.dart';

// One creature, Pokédex-style (user 2026-07-17): the element backdrop up top
// with the monster art straddling into a white sheet below, a short description
// under the name, and element-coloured tabs for General / Stats / Evolution /
// Abilities. Resolves the creature against the controller on every build so
// rename/evolve/release updates always reflect.
class CreatureDetailScreen extends StatefulWidget {
  /// Null when [previewCreature] is given instead.
  final String? creatureId;

  /// Renders this creature directly rather than looking [creatureId] up in
  /// [CreaturesController] — the starter-preview screen's use case: a rolled
  /// but not-yet-adopted [CreatureInstance] that has no id and isn't in the
  /// controller's list at all (user 2026-09-02: "Dieser Screen bei choose
  /// your starter soll 1:1 so aussehen wie der Monsterdetailscreen").
  final CreatureInstance? previewCreature;

  /// Replaces the Release button (and, in Dev Mode, its dev buttons) at the
  /// foot of the General tab — the starter preview swaps that whole block
  /// for its own "Choose" button, since none of Release/rename/evolve make
  /// sense on a creature that isn't owned yet.
  final Widget? footer;

  /// Opens the Stats tab's Lvl-1/Max toggle already set (user 2026-09-14) —
  /// the wild-catch preview wants MAX by default (the decision-relevant
  /// question is this wild's ceiling, not its current hunt-encounter level),
  /// while every other caller leaves this null and gets today's default
  /// (the creature's own real level, toggle off).
  final int? initialRefLevel;

  const CreatureDetailScreen({
    super.key,
    this.creatureId,
    this.previewCreature,
    this.footer,
    this.initialRefLevel,
  }) : assert(
         (creatureId == null) != (previewCreature == null),
         'pass exactly one of creatureId or previewCreature',
       );

  @override
  State<CreatureDetailScreen> createState() => _CreatureDetailScreenState();
}

/// Positions the Stats tab's info popover (see
/// [_CreatureDetailScreenState._showStatInfo]): right-docked at a fixed
/// margin from the screen's own edge regardless of [anchorY], and above the
/// tapped row when there's room, below it otherwise — never past any edge,
/// because [getPositionForChild] runs AFTER the child is measured and can
/// clamp against its real size instead of a guessed one.
class _StatInfoLayout extends SingleChildLayoutDelegate {
  final double anchorY;
  static const double _margin = 16;
  static const double _gap = 8;

  const _StatInfoLayout({required this.anchorY});

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final left = size.width - _margin - childSize.width;
    double top = anchorY - _gap - childSize.height;
    if (top < _margin) top = anchorY + _gap;
    return Offset(
      left.clamp(_margin, size.width - childSize.width - _margin),
      top.clamp(_margin, size.height - childSize.height - _margin),
    );
  }

  @override
  bool shouldRelayout(_StatInfoLayout oldDelegate) =>
      anchorY != oldDelegate.anchorY;
}

class _CreatureDetailScreenState extends State<CreatureDetailScreen> {
  final _ctrl = CreaturesController();
  final _settlement = SettlementController();
  bool _evolving = false;
  // Which detail tab is shown: 0 General · 1 Stats · 2 Evolution · 3 Abilities.
  int _tab = 0;

  // ── THE VOXEL SKIN ──
  // A species with baked block art (Tidelord) gets the whole page drawn as
  // blocks too (user 2026-11-03: "ganzes UI"): stepped corners, flat tones,
  // hard shadows, a pixel face, bars cut into blocks. Set from [build]; every
  // helper below asks [_sh] / [_vox] instead of hard-coding a look, so every
  // other species' screen is exactly what it was.
  bool _vox = false;
  Color _elem = CreamPalette.tan;

  ShapeBorder _sh({
    double radius = FoE.radius,
    BorderSide side = BorderSide.none,
  }) => _vox
      ? VoxelShape(notch: radius >= 12 ? 3 : (radius >= 8 ? 2 : 1))
      : FoE.facet(radius: radius, side: side);

  // â
  /// Which gene the Stats tab's bars are drawn from — see [GeneBarToggle].
  bool _barsShowGrowth = false;

  /// The Stats tab's level-preview override (user 2026-09-14: "einen
  /// Umschaltmodus, um das Monster in Lvl 1 und Max Level zu versetzen —
  /// bei den bereits gefangenen Monster und bei den noch nicht gefangenen").
  /// Null shows the creature at its own real [CreatureInstance.level] (today's
  /// behaviour, unchanged); 1 or [kCreatureMaxLevel] recompute every stat at
  /// that shared level instead, WITHOUT touching the real `level` field —
  /// see [CreatureInstance.statValueAtLevel]. Comparing two individuals only
  /// means something at a level they both actually reach, which is exactly
  /// why the "beats your best" marker below only lights up once one of these
  /// is picked.
  int? _refLevel;

  @override
  void initState() {
    super.initState();
    _refLevel = widget.initialRefLevel;
  }

  /// The Stats tab's "what is this for" popover (user 2026-09-06: "wenn ich
  /// auf die Namen der Stats klicke, soll eine kleine Box erscheinen ...
  /// nicht beim hovern sondern wenn ich darauf klicke/drücke. Dann soll eine
  /// Box erscheinen, welche ich wieder wegklicken kann") — a plain [Tooltip]
  /// was tried first, but Flutter shows one on mouse HOVER regardless of
  /// `triggerMode` the moment a pointer device is present, which is exactly
  /// the trigger the user asked NOT to have. A hand-rolled [OverlayEntry],
  /// same pattern [CollectionScreen]'s filter menu already uses (a
  /// full-screen translucent barrier to catch the dismiss-tap, a box
  /// positioned at the tap point), only ever opens on an explicit tap.
  OverlayEntry? _statInfoOverlay;

  void _closeStatInfo() {
    _statInfoOverlay?.remove();
    _statInfoOverlay = null;
  }

  void _showStatInfo(Offset tapPos, CreatureStat stat, Color element) {
    _closeStatInfo();
    _statInfoOverlay = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _closeStatInfo,
            ),
          ),
          Positioned.fill(
            // Docked to the right, above the tapped row (user 2026-09-06:
            // "kann es sein, dass die Toolbox aus dem Fenster geht. Diese
            // bitte immer rechts über dem Balken machen, so dass sie immer
            // sichtbar ist") — a box centred under the tap point could run
            // past either screen edge depending on which stat's row it was;
            // [_StatInfoLayout] only knows the box's actual measured size
            // AFTER layout, so it (like Flutter's own Tooltip/PopupMenu) is
            // the one place that can dock it fully on-screen regardless of
            // how long a given stat's description happens to be.
            child: CustomSingleChildLayout(
              delegate: _StatInfoLayout(anchorY: tapPos.dy),
              child: Pressable(
                // Tapping the box itself also dismisses it (user: "wieder
                // wegklicken") rather than requiring a tap on the barrier.
                onTap: _closeStatInfo,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: 220,
                    padding: const EdgeInsets.all(10),
                    decoration: ShapeDecoration(
                      // Dark glass in the element's own deep tone, like every
                      // card on this page.
                      color: Color.lerp(element, Colors.black, 0.62),
                      shape: _sh(
                        radius: 10,
                        side: const BorderSide(color: Color(0x59FFFFFF)),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stat.label,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          stat.description,
                          style: const TextStyle(color: _inkDim, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_statInfoOverlay!);
  }

  @override
  void dispose() {
    _closeStatInfo();
    super.dispose();
  }

  // THE SHEET IS PARCHMENT (user 2026-07-27: "der Monster Detailscreen soll
  // ebenfalls den Hellen Hintergrund haben mit der Verzierung").
  //
  // The Pokédex layout is unchanged — a colourful element backdrop up top with
  // the monster straddling the seam, and everything else on a sheet below. That
  // sheet was FoE.panelDark, the deeper tan the game's chrome uses; it is now
  // the same page every other screen is printed on, meander bordure included.
  // ── Das Papier trägt das Element (user 2026-07-31) ─────────
  // "Nimm anstelle des beigen hintergrunds, jeweils eine andere Ausprägung der
  //  Farbe des Elements"
  //
  // One beige page for every monster in the game, under a backdrop that was
  // already shouting the type. The page is now the monster's own colour — but
  // the SAME colour it always was in every other respect: the ink, the hairlines
  // and the bordure are unchanged, and they only stay legible because the tint
  // is controlled rather than mixed.
  //
  // Hue comes from the element, LIGHTNESS is fixed here. Blending the raw
  // element colour into the parchment would have made a shadow monster's page
  // nearly black and a light monster's white, and the dark-brown ink over it
  // would have been unreadable in one of those two directions.

  /// The sheet in the kit's paper — the higher [lightness] (the callers pass
  /// 0.16 at the top of the sheet, 0.10 at its foot) giving the lighter end. LIGHT
  /// since the Holz palette (user 2026-09-19); it was dark tinted paper before.
  static Color _paper(Color element, double lightness) {
    // The kit's paper (Holz), the higher lightness giving the lighter end — with
    // a breath of the element's hue (7 %), so a fire monster's sheet is not quite
    // a water monster's. The ink over it is the kit's, legible by construction.
    final base = Color.lerp(
      CreamPalette.paperBottom,
      CreamPalette.paperTop,
      ((lightness - 0.10) / 0.06).clamp(0.0, 1.0),
    )!;
    return Color.lerp(base, element, 0.07)!;
  }

  // ── THE PAGE IS THE ELEMENT (user 2026-09-21, "13" of the Monsterdetail
  // proposals: "Monster in der Mitte"): the element colour runs over the WHOLE
  // screen and everything on it is white on dark glass, so the text tones are
  // white now, not the paper ink they were.
  static const _ink = Colors.white; // primary text
  // Literal ARGB rather than withValues: these are used in `const` widgets all
  // over this file, and a computed colour is not a constant.
  static const _inkDim = Color(0xCCFFFFFF); // white @ 80 %
  // Bar / chip fill: a lighter well in the dark glass.
  static const _track = Color(0x33FFFFFF); // white @ 20 %

  /// The dialogs and menus are still cream paper (they float above the page,
  /// like everywhere else in the app), so THEY keep the dark brown ink.
  static const _dlgInk = kBoxInk;
  static const _dlgDim = Color(0x942A1A0C); // ink @ 58 %
  static const _dlgTrack = Color(0x212A1A0C); // ink @ 13 %

  /// True for the starter-preview use ([widget.previewCreature]) — gates off
  /// every action that assumes a real, owned, persisted creature (rename,
  /// evolve, release) since none of them have anywhere valid to write to.
  bool get _isPreview => widget.previewCreature != null;

  /// Never caught before (user 2026-09-14: "bitte noch anzeigen, falls ein
  /// Monster new ist") — same "discovered" test the Bestiary already uses
  /// (owns at least one of the species), so a wild preview and the starter
  /// preview both read it the same way a fresh catch would. Only checked in
  /// preview mode: viewing an OWNED creature's own screen means you already
  /// own it, so the question never arises there.
  bool _isNewSpecies(CreatureInstance creature) =>
      _isPreview &&
      !_ctrl.creatures.any((c) => c.speciesId == creature.speciesId);

  CreatureInstance? get _creature {
    final preview = widget.previewCreature;
    if (preview != null) return preview;
    for (final c in _ctrl.creatures) {
      if (c.id == widget.creatureId) return c;
    }
    return null;
  }

  Future<void> _evolve(CreatureInstance creature) async {
    setState(() => _evolving = true);
    final before = creature.displayName;
    final err = await _ctrl.evolve(creature);
    if (!mounted) return;
    setState(() => _evolving = false);
    // Messages are back (user 2026-11-02).
    if (err != null) {
      context.snack(err, error: true);
    } else {
      Feel.fanfare();
      context.snack('✨ $before evolved into ${creature.displayName}!');
    }
  }

  // Rename dialog, styled to match this screen (dark sheet, Outfit font, the
  // creature's element as the accent) rather than the global FoE gold theme
  // (user 2026-07-18).
  Future<void> _rename(CreatureInstance creature) async {
    final element = creature.species?.element.color ?? CreamPalette.tan;
    final controller = TextEditingController(text: creature.nickname ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _paper(element, 0.16),
        shape: _sh(radius: 20),
        title: Text(
          'Rename',
          style: GoogleFonts.outfit(
            color: _dlgInk,
            fontSize: 18,
            fontWeight: FontWeight.w400,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          cursorColor: element,
          style: GoogleFonts.outfit(color: _dlgInk, fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Empty = species name',
            hintStyle: GoogleFonts.outfit(color: _dlgDim, fontSize: 13),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: _dlgTrack),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: element, width: 2),
            ),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.outfit(
                color: _dlgDim,
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(
              'Save',
              style: GoogleFonts.outfit(
                color: element,
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
    if (name != null) await _ctrl.rename(creature, name);
  }

  Future<void> _release(CreatureInstance creature) async {
    // Asked up front so the dialog can SAY why, instead of the old flow
    // (confirm, then nothing happens) — the reason replaces the question.
    final blocked = _ctrl.releaseBlocker(creature);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: CreamPalette.paperTop,
        shape: _sh(radius: 12, side: BorderSide(color: CreamPalette.tan)),
        title: Text(
          blocked == null ? 'Release?' : 'Cannot release',
          style: FoE.title(size: 15).copyWith(color: _dlgInk),
        ),
        content: Text(
          blocked ?? '${creature.displayName} leaves you forever.',
          style: FoE.label(size: 13).copyWith(color: _dlgInk),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              blocked == null ? 'Cancel' : 'OK',
              style: FoE.dim(size: 13).copyWith(color: _dlgDim),
            ),
          ),
          if (blocked == null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'Release',
                style: FoE.label(size: 13).copyWith(
                  color: CreamPalette.warn,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
        ],
      ),
    );
    if (ok == true) {
      final error = await _ctrl.release(creature);
      if (!mounted) return;
      if (error != null) {
        context.snack(error, error: true);
        return;
      }
      Navigator.of(context).pop();
    }
  }

  Future<void> _usePotion(ItemDef def, CreatureInstance creature) async {
    final err = await _ctrl.useItemOn(def.id, creature);
    if (!mounted) return;
    if (err != null) {
      context.snack(err, error: true);
    } else {
      setState(() {});
    }
  }

  // ── Layout ────────────────────────────────────────────────
  // "MONSTER IN DER MITTE" (user 2026-09-21, variant 13 of the Monsterdetail
  // proposals). The element colour runs over the WHOLE screen; the monster
  // stands large in the middle with its level and XP under it; the active tab's
  // content is split into a LEFT and a RIGHT column of dark glass cards either
  // side of it, so two areas are readable at once and the monster never leaves
  // the screen. The four tabs sit along the bottom.
  //
  // Every tab body below still does what it did — what changed is that each now
  // returns TWO columns ([_columnsFor]) instead of one long list.
  @override
  Widget build(BuildContext context) {
    final scaffoldElement =
        _creature?.species?.element.color ?? CreamPalette.tan;
    return Scaffold(
      backgroundColor: Color.lerp(scaffoldElement, Colors.black, 0.35),
      body: ListenableBuilder(
        listenable: Listenable.merge([_ctrl, _settlement]),
        builder: (context, _) {
          final creature = _creature;
          if (creature == null) {
            return Center(
              child: Text(
                'Creature not found',
                style: FoE.label().copyWith(color: _ink),
              ),
            );
          }
          final species = creature.species;
          final element = species?.element.color ?? CreamPalette.tan;
          // EVERY species now (user 2026-11-03: "der Monsterdetailscreen soll
          // noch überall angepasst werden wie bei tidelord") — only the art's
          // own scale-up stays Tidelord's, see [_leftArt].
          _vox = true;
          _elem = element;
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: _vox
                    ? VoxelBackdrop(color: element)
                    : species == null
                    ? ColoredBox(color: element)
                    : CreatureBackdrop(
                        element: species.element,
                        radius: 0,
                        child: const SizedBox.expand(),
                      ),
              ),
              SafeArea(
                child: MediaQuery(
                  data: MediaQuery.of(context),
                  child: DefaultTextStyle.merge(
                    style: _vox
                        ? Voxel.text(color: _ink)
                        : GoogleFonts.outfit(color: _ink),
                    child: LayoutBuilder(
                      builder: (context, c) =>
                          _stage(context, c, creature, species, element),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// The whole screen ("Glas auf Farbe", variant 11, with the tab rail of variant
  /// 3 — user 2026-09-21): the monster on the left with its level and XP under
  /// it, a rail of four tabs next to it, and the header and the tab's content in
  /// the space that is left.
  Widget _stage(
    BuildContext context,
    BoxConstraints c,
    CreatureInstance creature,
    SpeciesDef? species,
    Color element,
  ) {
    final w = c.maxWidth;
    // A FRACTION of the width, clamped (responsiveness pass 2026-09-18) — a
    // landscape phone's long axis runs from ~667 px to this app's 932 px cap.
    final artW = (w * 0.27).clamp(190.0, 260.0);
    const railW = 70.0;
    const gap = 8.0;
    final contentLeft = artW + railW + gap * 2;
    return Stack(
      children: [
        // The monster, big, on the element colour.
        Positioned(
          left: 0,
          width: artW,
          top: 40,
          bottom: 84,
          child: IgnorePointer(child: _leftArt(creature)),
        ),
        // Level and XP under it.
        Positioned(
          left: 18,
          width: artW - 36,
          bottom: 10,
          child: _levelBlock(creature, element),
        ),
        // The kit's one leaving button, top right like every other screen's
        // (user 2026-09-22): an arrow, because this page opens over a list.
        Positioned(
          top: 8,
          right: 12,
          child: _vox
              ? Pressable(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: KitCloseButton.size,
                    height: KitCloseButton.size,
                    alignment: Alignment.center,
                    decoration: ShapeDecoration(
                      color: Voxel.tone(element, 3),
                      shape: const VoxelShape(notch: 2),
                      shadows: voxelDrop(depth: 2),
                    ),
                    child: const VoxelIcon(VoxelGlyph.back, size: 20),
                  ),
                )
              : KitCloseButton(
                  back: true,
                  color: element,
                  onTap: () => Navigator.of(context).pop(),
                ),
        ),
        // THE TABS AS A RAIL (variant 3): they cost 70 px of width instead of a
        // 56-px row of height, and the height is what the Stats page needs.
        // Centred on the screen's height (user 2026-09-21).
        Positioned(
          left: artW + gap,
          width: railW,
          top: 12,
          bottom: 12,
          child: Center(child: _tabRail(creature, element)),
        ),
        Positioned(
          left: contentLeft,
          right: 12,
          top: 8,
          bottom: 8,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: KitCloseButton.size + 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _header(creature, species, element)),
                    // The way to the Combat School sits on the Abilities tab.
                    if (_tab == 3 && !_isPreview && _hasCombatSchool)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: _learnPill(),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Expanded(child: _body(creature, species, element)),
              // The caller's footer (the starter preview's "Choose" button) stays
              // put across all four tabs (user 2026-09-02).
              if (widget.footer != null) ...[
                const SizedBox(height: 8),
                widget.footer!,
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// LEVEL AND EP under the monster (user 2026-09-21, from a picture): "Level 26"
  /// in the monster's own type colour, a flat rounded bar filled in a lighter
  /// tint of it on a darker tone of the page (user 2026-09-29: "Level n und
  /// Erfahrungsbalken sollen auch in der entsprechenden Typfarben gehalten
  /// werden" — the bar was plain gold before, the one thing on the page not
  /// tinted to the element already painted everywhere around it) — and
  /// "3120 / 4400 EP" under it.
  Widget _levelBlock(CreatureInstance creature, Color element) {
    final atMax = creature.level >= kCreatureMaxLevel;
    final need = atMax ? 1 : xpToNextLevel(creature.level);
    final frac = atMax ? 1.0 : (creature.xp / need).clamp(0.0, 1.0);
    final fill = Color.lerp(element, Colors.white, 0.4)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Level ${creature.level}',
          style: TextStyle(
            color: fill,
            fontSize: 19,
            fontWeight: FontWeight.w400,
            shadows: const [Shadow(color: Color(0xCC000000), offset: Offset(0, 1))],
          ),
        ),
        const SizedBox(height: 5),
        if (_vox)
          VoxelBar(value: frac, color: fill, height: 14)
        else
          ClipRRect(
            borderRadius: vr(7),
            child: SizedBox(
              height: 14,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: Color.lerp(element, Colors.black, 0.45)!),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: frac,
                      heightFactor: 1,
                      child: ColoredBox(color: fill),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 4),
        Text(
          atMax ? 'MAX' : '${creature.xp} / $need EP',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 12,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  /// The active tab's content. Every tab is laid out to fit the height it is given
  /// without scrolling (user 2026-09-21).
  Widget _body(CreatureInstance creature, SpeciesDef? species, Color element) =>
      switch (_tab) {
        1 => _statsBody(creature, element),
        2 => _evolutionBody(creature),
        3 => _abilityBody(creature),
        _ => _generalBody(creature, element),
      };

  /// The monster's art with its element-tinted drop shadow — the same figure
  /// every monster display uses ([CreatureFigure]), decoded at the size it is
  /// drawn (user 2026-08-29: "die Monsterassets werden sehr langsam geladen").
  Widget _leftArt(CreatureInstance creature) => LayoutBuilder(
    builder: (context, constraints) {
      final figure = CreatureFigure(
        imageUrl: creature.imageUrl,
        element: creature.species?.element ?? CreatureElement.fire,
        decodeSize: constraints.maxHeight,
      );
      // The 1.3× lift is for the baked voxel renders, whose frames leave a
      // wide margin round the monster; a plain sprite already fills its box.
      if (!_vox || !MonsterSheets.hasBaked(creature.speciesId)) return figure;
      // The three-step block plinth under the creature was removed (user
      // 2026-11-03: "Diese drei Balken können entfernt werden").
      return Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            bottom: 26,
            child: Transform.scale(
              scale: 1.3,
              alignment: Alignment.bottomCenter,
              child: figure,
            ),
          ),
        ],
      );
    },
  );

  /// THE TAB RAIL: four keys with a symbol over a short word; the live one is
  /// white, the others dark glass. Release moved OFF this rail again (user
  /// 2026-09-29: "unterhalb von Strengths, dafür Work Kasten kleiner
  /// machen") — see [_generalBody]'s right column.
  Widget _tabRail(CreatureInstance creature, Color element) {
    const tabs = [
      ('❤️', 'General'),
      ('📊', 'Stats'),
      ('🧬', 'Evolution'),
      ('⚔️', 'Abilities'),
    ];
    // The Evolution tile itself says so (user 2026-09-29: "Die Kachel
    // Evolution soll zeigen, dass eine Evolution möglich ist") — the same
    // green arrow the collection tile wears, so a player never has to open
    // the tab just to learn it is worth opening.
    const glyphs = [
      VoxelGlyph.heart,
      VoxelGlyph.bars,
      VoxelGlyph.dna,
      VoxelGlyph.sword,
    ];
    final canEvolve = !_isPreview && creature.canEvolve;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < tabs.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          Pressable(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _tab = i),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOut,
                  height: 66,
                  width: double.infinity,
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    color: _vox
                        ? (_tab == i
                              ? Voxel.tone(element, 4)
                              : Voxel.tone(element, 1))
                        : (_tab == i ? Colors.white : const Color(0x47000000)),
                    shape: _sh(radius: 14),
                    shadows: _vox ? voxelDrop(depth: _tab == i ? 1 : 3) : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_vox)
                        VoxelIcon(
                          glyphs[i],
                          size: 24,
                          color: _tab == i
                              ? Voxel.tone(element, 0)
                              : Colors.white,
                          shadow: _tab != i,
                        )
                      else
                        Text(tabs[i].$1, style: const TextStyle(fontSize: 20)),
                      const SizedBox(height: 3),
                      Text(
                        tabs[i].$2,
                        maxLines: 1,
                        style: TextStyle(
                          color: _tab == i
                              ? Color.lerp(element, Colors.black, 0.55)
                              : _inkDim,
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                if (i == 2 && canEvolve)
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Semantics(
                      label: 'Evolution ready',
                      container: true,
                      child: _vox
                          ? const VoxelIcon(
                              VoxelGlyph.arrowUp,
                              size: 22,
                              color: Color(0xFF2FD37A),
                            )
                          : PixelIcon(
                              Icons.arrow_upward_rounded,
                              size: 20,
                              color: Color(0xFF2FD37A),
                              shadows: [
                                Shadow(color: Color(0xCC000000), blurRadius: 3),
                                Shadow(
                                  color: Color(0x99000000),
                                  offset: Offset(0, 1.5),
                                ),
                              ],
                            ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Name, gender, rename, NEW — and under it the facts you always want:
  /// level, power, rarity, element (they used to be spread over three corners).
  Widget _header(
    CreatureInstance creature,
    SpeciesDef? species,
    Color element,
  ) {
    // The level chip in the type colour too (user 2026-09-29: "Die
    // Levelanzeige unterhalb des Namens … ist noch nicht in der Farbe des
    // Elements") — every OTHER fact on this page already reads in [element]
    // (the backdrop, the back button, the Level/XP block under the portrait);
    // this chip was still the kit's flat gold.
    final levelTint = Color.lerp(element, Colors.white, 0.35)!;
    const shadow = [
      Shadow(color: Color(0xAA000000), offset: Offset(0, 1)),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                creature.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.start,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 21,
                  fontWeight: FontWeight.w400,
                  shadows: shadow,
                ),
              ),
            ),
            Transform.translate(
              offset: const Offset(4, -7),
              child: Text(
                creature.gender.symbol,
                style: TextStyle(
                  color: Color.lerp(creature.gender.color, Colors.white, 0.5),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  shadows: shadow,
                ),
              ),
            ),
            // Never caught before (user 2026-09-14) — same badge shape the
            // build menu's own MAX/QUEUE FULL tag uses.
            if (_isNewSpecies(creature))
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: ShapeDecoration(
                    color: CreamPalette.gold,
                    shape: _sh(radius: 6),
                  ),
                  child: Text(
                    'NEW',
                    style: FoE.dim(size: 9).copyWith(
                      color: CreamPalette.ink,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
            // Small edit (rename) button. Not owned yet in preview — nothing
            // valid to rename.
            if (!_isPreview)
              Pressable(
                onTap: () => _rename(creature),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: _vox
                      ? const VoxelIcon(
                          VoxelGlyph.edit,
                          size: 16,
                          color: _inkDim,
                        )
                      : PixelIcon(Icons.edit, size: 15, color: _inkDim),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.start,
          spacing: 6,
          runSpacing: 4,
          children: [
            _chip(
              'Lv ${creature.level}',
              bg: levelTint,
              fg: levelTint.computeLuminance() > 0.45
                  ? CreamPalette.ink
                  : Colors.white,
            ),
            _chip('⚡ ${totalPower(creature)}'),
            if (species != null) ...[
              _chip(species.rarity.label, dot: species.rarity.color),
              _chip('${species.element.emoji} ${species.element.label}'),
            ],
          ],
        ),
      ],
    );
  }

  Widget _chip(String text, {Color? bg, Color fg = Colors.white, Color? dot}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
        decoration: ShapeDecoration(
          color: bg ?? (_vox ? Voxel.tone(_elem, 1) : const Color(0x47000000)),
          shape: _sh(radius: 9),
          shadows: _vox ? voxelDrop(depth: 2) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot != null) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: dot,
                  shape: BoxShape.rectangle,
                ),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              text,
              style: TextStyle(
                color: fg,
                fontSize: 11,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      );

  /// A CARD ON THE SHEET — a raised leaf of lighter paper with a hairline and a
  /// small cast.
  ///
  /// The tab bodies were loose rows floating directly on the parchment: bars,
  /// captions and stat lines all at the same visual level, with only blank space
  /// between groups. On the Stats tab that is thirteen rows and three headings
  /// with nothing holding them apart.
  Widget _panel({
    String? title,
    required Widget child,
    TextAlign titleAlign = TextAlign.left,
    double gap = 9,
  }) => Padding(
    padding: EdgeInsets.only(bottom: gap),
    child: _recess(
      radius: 14,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: title == null
          ? child
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _panelTitle(title, textAlign: titleAlign),
                const SizedBox(height: 10),
                child,
              ],
            ),
    ),
  );

  /// A [_panel] that TAKES THE HEIGHT it is given — put it in an [Expanded] slot
  /// of a column. [header] sits on top and [child] gets what is left, so a column
  /// with one of these ends exactly where its neighbour column does (user
  /// 2026-09-21: "beide Seiten zusammen gleich hoch").
  Widget _fillPanel({
    Widget? header,
    required Widget child,
    int flex = 1,
    double gap = 0,
  }) => Expanded(
    flex: flex,
    child: Padding(
      padding: EdgeInsets.only(bottom: gap),
      child: _recess(
        radius: 14,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (header != null) ...[header, const SizedBox(height: 8)],
            Expanded(child: child),
          ],
        ),
      ),
    ),
  );

  /// A CARD ON THE SHEET.
  ///
  /// It used to be a HOLLOW cut into the parchment (user 2026-07-29: "diese
  /// Boxen sollen so aussehen, als wären sie nach innen versetzt"): inner
  /// shadows down the walls, a lit far wall, a hard white line capping it. Taken
  /// out again on 2026-07-31 ("Ich meine die Vertiefungen der Boxen bei
  /// condition, strenghts und den tabs etc.") — six sculpted wells stacked down
  /// one screen is a lot of relief for boxes whose job is to group three lines
  /// of text, and every one of them drew four gradients to say so.
  ///
  /// What is left is what actually did the grouping: a slightly darker fill and
  /// a hairline. The tab bar's groove is built from this too, so the control and
  /// the cards under it stay the same material.
  Widget _recess({
    required Widget child,
    required double radius,
    EdgeInsets padding = EdgeInsets.zero,
  }) => Container(
    width: double.infinity,
    padding: padding,
    decoration: ShapeDecoration(
      // DARK GLASS over the element colour (variant 13): black at ~28 % keeps
      // the page's hue and makes white text legible on any element.
      color: _vox ? Voxel.tone(_elem, 1) : const Color(0x47000000),
      shape: _sh(
        radius: radius,
        side: const BorderSide(color: Color(0x24FFFFFF)),
      ),
      shadows: _vox ? voxelDrop() : null,
    ),
    child: child,
  );

  /// A panel's heading — small, spaced capitals, cut into the card.
  static Widget _panelTitle(
    String label, {
    Widget? trailing,
    TextAlign textAlign = TextAlign.left,
  }) => Row(
    children: [
      Expanded(
        child: Text(
          label.toUpperCase(),
          textAlign: textAlign,
          // NO cut-in highlight (2026-07-31): the white line under the letters
          // is how you carve text INTO a surface, and there is no hollow left
          // for it to be carved into.
          style: TextStyle(
            color: _inkDim,
            fontSize: 11,
            fontWeight: FontWeight.w400,
            letterSpacing: 1,
          ),
        ),
      ),
      if (trailing != null) trailing,
    ],
  );

  // ── Tabs ──────────────────────────────────────────────────
  /// GENERAL, two columns of the SAME height (user 2026-09-21: "Work oben rechts,
  /// Strengths unten rechts mit 4 Werten, Condition und About links").
  ///
  /// LEFT: Condition (the HP bar, the heal / potion control, what it is busy with)
  /// and under it About, which takes the rest. RIGHT: Work, which takes the rest,
  /// and under it Strengths — its four best stats. Each column has exactly one
  /// panel that stretches, so both end on the same line.
  Widget _generalBody(CreatureInstance creature, Color element) {
    final hpFrac = creature.maxHp > 0 ? creature.hp / creature.maxHp : 0.0;
    // Keep the HP-bar colour thresholds identical to the collection card's
    // (2026-07-18): red is the signal for "needs attention", not only K.O.
    final hpColor = hpFrac < 0.3
        ? FoE.danger
        : hpFrac < 0.6
        ? CreamPalette.gold
        : const Color(0xFF7CE0A8);
    final top = topStats(creature, count: 4);
    final care = creature.isHealing
        ? _healingInline(creature, element)
        : creature.hp < creature.maxHp
        ? _potionInline(creature, element)
        : null;
    final busy = _busyLine(creature);
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panel(
          title: 'Condition',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _barRow(
                'HP',
                '${creature.hp} / ${creature.maxHp}',
                hpFrac,
                hpColor,
                bottomPad: care == null && busy == null ? 0 : 8,
              ),
              ?care,
              if (busy != null)
                Padding(
                  padding: EdgeInsets.only(top: care == null ? 0 : 8),
                  child: Text(
                    busy,
                    style: const TextStyle(color: _ink, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
        _aboutPanel(creature),
      ],
    );
    // Not shown in preview (user 2026-09-02) — the caller's own footer takes
    // that spot instead, since Release assumes a creature that is owned. The
    // starter never gets one at all (user 2026-09-02: "Das Startmonster kann
    // aber niemals entlassen werden").
    final canRelease = !_isPreview && !creature.isStarter;
    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _workPanel(creature, gap: top.isEmpty ? 0 : 9),
        if (top.isNotEmpty)
          _panel(
            title: 'Strengths',
            gap: canRelease ? 8 : 0,
            child: Column(
              children: [
                for (var i = 0; i < top.length; i += 2) ...[
                  if (i > 0) const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: _strengthTile(top[i], creature)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: i + 1 < top.length
                            ? _strengthTile(top[i + 1], creature)
                            : const SizedBox(),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        // Release moved here (user 2026-09-29: "unterhalb von Strengths,
        // dafür Work Kasten kleiner machen") — Work is an Expanded
        // [_fillPanel] slot, so it gives up exactly this row's height on its
        // own; the column's total stays the same as the left one's.
        if (canRelease) _releaseButton(creature),
      ],
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: left),
        const SizedBox(width: 10),
        Expanded(child: right),
      ],
    );
  }

  /// What the monster is busy with besides a work post (which has its own card):
  /// learning a move, waiting for a class, breeding, on a trip. Null when it is
  /// simply free.
  String? _busyLine(CreatureInstance creature) {
    if (creature.isTraining) {
      final id = creature.trainingAbilityId;
      final name = id == null ? 'a move' : (kAbilityDefs[id]?.name ?? id);
      return '📖 Learning $name at the Combat School · '
          '${_fmt(creature.trainingRemaining)} left.';
    }
    if (creature.isQueuedForTraining) {
      return '📖 Waiting in line at the Combat School.';
    }
    if (_ctrl.isOnExpedition(creature.id)) return '🎒 Away on an expedition.';
    if (_ctrl.isBreeding(creature.id)) return '🥚 Busy breeding.';
    if (creature.isQueuedForHealing) {
      return '🩹 Waiting in line for a healing bed.';
    }
    return null;
  }

  /// Who it is: the species text, its stage, where it came from, and how many
  /// of the species you own — and, small and out of the way in the corner, Release.
  Widget _aboutPanel(CreatureInstance creature) {
    final species = creature.species;
    final desc = species?.description ?? '';
    final parentA = creature.parentAId == null
        ? null
        : _ctrl.byId(creature.parentAId!);
    final parentB = creature.parentBId == null
        ? null
        : _ctrl.byId(creature.parentBId!);
    final origin = creature.isStarter
        ? 'Your first companion.'
        : (creature.parentAId != null || creature.parentBId != null)
        ? 'Bred from ${parentA?.displayName ?? 'a released parent'} × '
              '${parentB?.displayName ?? 'a released parent'}.'
        : null;
    final owned = _ctrl.creatures
        .where((c) => c.speciesId == creature.speciesId)
        .length;
    Widget fact(String k, String v) => Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Text(k, style: const TextStyle(color: _inkDim, fontSize: 12)),
          const Spacer(),
          Text(
            v,
            style: const TextStyle(
              color: _ink,
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
    return _fillPanel(
      header: _panelTitle('About'),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              // Species text is still mostly unwritten (user 2026-09-29: "bei
              // About könnte ein kleiner Infotext … diese werden dann noch
              // gefüllt werden, daher nur Platzhaltertext") — an empty About
              // said nothing at all, which read as a bug rather than content
              // still to come.
              desc.isNotEmpty ? desc : 'No info yet — coming soon.',
              style: TextStyle(
                color: _inkDim,
                fontSize: 12,
                height: 1.3,
                fontStyle: desc.isEmpty ? FontStyle.italic : FontStyle.normal,
              ),
            ),
            if (origin != null) ...[
              SizedBox(height: desc.isEmpty ? 0 : 6),
              Text(
                origin,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ],
            const SizedBox(height: 6),
            fact('Form', 'Stage ${creature.stage + 1} of 3'),
            fact('Level', '${creature.level} / $kCreatureMaxLevel'),
            if (!_isPreview) fact('You own', '$owned of this species'),
          ],
        ),
      ),
    );
  }

  /// Release, below Strengths on the General tab's right column (user
  /// 2026-09-29: "unterhalb von Strengths, dafür Work Kasten kleiner
  /// machen" — Work uses [_fillPanel], an Expanded slot, so it shrinks by
  /// itself the moment this row takes its share of the column's fixed
  /// height; nothing else has to change). An outlined coral button, not a
  /// filled one: still deliberately quieter than the gold Evolve button so
  /// it is never the thing an idle thumb lands on (user 2026-09-21: "Release
  /// ist schwer zu erkennen und sollte nicht zu prominent sein, damit es
  /// nicht aus versehen angewählt wird" — the confirm dialog in [_release] is
  /// the other half of that same guard).
  static const Color _releaseTint = Color(0xFFFFB4A2);

  Widget _releaseButton(CreatureInstance creature) => Pressable(
    behavior: HitTestBehavior.opaque,
    onTap: () => _release(creature),
    child: Container(
      height: 30,
      width: double.infinity,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        shape: _sh(
          radius: 10,
          side: const BorderSide(color: _releaseTint, width: 1.2),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          PixelIcon(Icons.logout_rounded, size: 13, color: _releaseTint),
          SizedBox(width: 6),
          Text(
            'Release',
            style: TextStyle(
              color: _releaseTint,
              fontSize: 11,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    ),
  );

  /// One of the creature's best stats: name left, value right, on a lighter well
  /// in the glass.
  Widget _strengthTile(CreatureStat stat, CreatureInstance creature) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: ShapeDecoration(
          color: const Color(0x29FFFFFF),
          shape: _sh(
            radius: 10,
            side: const BorderSide(color: Color(0x40FFFFFF)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                stat.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _inkDim,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${creature.statValue(stat)}',
              style: const TextStyle(
                color: _ink,
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      );

  // The two utility stats that ride along on expeditions — carry (loot hauled)
  // and catchRate (this creature's Fangwert). Neither is a workshop role, so
  // they live in their own group rather than under Work.
  static const _expeditionStats = [CreatureStat.carry, CreatureStat.catchRate];

  /// STATS, in two columns (user 2026-09-21: "Werte: muss umschaltbar sein für
  /// Lvl 1, Max, pro Level etc.").
  ///
  /// LEFT: the two switches on top — WHICH LEVEL every number is worked out at
  /// (now, level 1, max level) and WHICH GENE the bars draw (the value, or the
  /// growth per level) — then Combat and Expedition. RIGHT: Work.
  Widget _statsBody(CreatureInstance creature, Color element) {
    // The Lvl-1/Max preview (user 2026-09-14) overrides which level every
    // number below is computed at — see [_refLevel]'s own doc comment.
    final atLevel = _refLevel ?? creature.level;
    final values = {
      for (final s in CreatureStat.values)
        s: creature.statValueAtLevel(s, atLevel),
    };
    // "Beats your best" — only meaningful once a SHARED reference level is
    // picked (comparing at each creature's own current level tells you nothing,
    // which is exactly why the switch exists). Excludes this creature itself;
    // empty when nothing else of this species is owned yet.
    final ownedRivals = _ctrl.creatures.where(
      (c) => c.speciesId == creature.speciesId && c.id != creature.id,
    );
    final bestOwnedValue = {
      for (final s in CreatureStat.values)
        s: _refLevel == null
            ? null
            : bestOwnedStatAtLevel(ownedRivals, s, _refLevel!),
    };
    // "Beats your best" on the GROWTH gene (user 2026-09-14) — a flat rate,
    // comparable exactly as rolled, so it marks regardless of the switch.
    final bestOwnedSlope = {
      for (final s in CreatureStat.values) s: bestOwnedGrowth(ownedRivals, s),
    };
    // WHICH GENE THE BARS DRAW (user 2026-07-27): the scale follows it, since a
    // growth of +1.6 against a stat of 80 would otherwise be a hairline.
    final barValues = _barsShowGrowth
        ? {for (final s in CreatureStat.values) s: (creature.statSlope[s] ?? 0)}
        : {for (final s in CreatureStat.values) s: values[s]!.toDouble()};
    final maxVal = barValues.values.reduce((a, b) => a > b ? a : b);
    int totalOf(List<CreatureStat> group) =>
        group.fold(0, (sum, s) => sum + values[s]!);

    // WHICH COLUMN READS AS THE HEADLINE follows the same switch the bars do
    // (user 2026-08-31): the chosen gene is bold and big, the other steps back.
    const bigStyle = TextStyle(
      color: _ink,
      fontSize: 12,
      fontWeight: FontWeight.w400,
    );
    const smallStyle = TextStyle(
      color: _inkDim,
      fontSize: 11,
      fontWeight: FontWeight.w400,
    );
    final valueStyle = _barsShowGrowth ? smallStyle : bigStyle;
    final growthStyle = _barsShowGrowth ? bigStyle : smallStyle;
    // Bars in a light tint of the element: the element colour itself would
    // vanish on a page of the same colour.
    final barColor = Color.lerp(element, Colors.white, 0.82)!;
    const better = Color(0xFF7CE0A8);

    // The group's summed value rides in its card's heading.
    Widget header(String label, int total) => _panelTitle(
      label,
      trailing: Text(
        '$total',
        style: const TextStyle(
          color: _ink,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
      ),
    );

    // A stat row: label · bar · current value · growth-per-level.
    Widget row(CreatureStat stat) {
      final growth = creature.statSlope[stat] ?? 0;
      final bestValue = bestOwnedValue[stat];
      final valueBeats = bestValue != null && values[stat]! > bestValue;
      final bestGrowth = bestOwnedSlope[stat];
      final growthBeats = bestGrowth != null && growth > bestGrowth;
      Widget num(String text, TextStyle style, bool beats) => SizedBox(
        width: 44,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (beats)
              const PixelIcon(Icons.arrow_drop_up, size: 16, color: better),
            Text(
              text,
              textAlign: TextAlign.right,
              style: beats
                  ? style.copyWith(color: better, fontWeight: FontWeight.w400)
                  : style,
            ),
          ],
        ),
      );
      return Row(
        children: [
          SizedBox(
            width: _vox ? 92 : 76,
            // Tap the name for what the stat is actually used for (user
            // 2026-09-06) — see [_showStatInfo].
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) =>
                  _showStatInfo(details.globalPosition, stat, element),
              child: Text(
                stat.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _ink, fontSize: 12),
              ),
            ),
          ),
          Expanded(
            child: _vox
                ? VoxelBar(
                    value: maxVal > 0 ? barValues[stat]! / maxVal : 0,
                    color: barColor,
                    height: 9,
                    block: 7,
                  )
                : RecessBar(
                    value: maxVal > 0 ? barValues[stat]! / maxVal : 0,
                    color: barColor,
                    height: 9,
                  ),
          ),
          const SizedBox(width: 4),
          num('${values[stat]}', valueStyle, valueBeats),
          num('+${growth.toStringAsFixed(1)}', growthStyle, growthBeats),
        ],
      );
    }

    // A group takes a share of its column's height in proportion to its rows (a
    // row counts 10, a heading 16), and spreads its rows evenly over what it got.
    Widget group(String label, List<CreatureStat> stats) => _fillPanel(
      flex: stats.length * 10 + 16,
      header: header(label, totalOf(stats)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final s in stats) row(s)],
      ),
    );

    // Read order Lv1 → Now → Max (user 2026-09-28: "Stats und Breeding Hut:
    // Lv1 dann Now dann Max Level"), same as the shared LevelRefToggle.
    final refIndex = switch (_refLevel) {
      1 => 0,
      null => 1,
      _ => 2,
    };
    final controls = Row(
      children: [
        Expanded(
          child: _glassSeg(
            [
              'Lv 1',
              'Now · Lv ${creature.level}',
              'Max · Lv $kCreatureMaxLevel',
            ],
            refIndex,
            (i) => setState(
              () => _refLevel = switch (i) {
                0 => 1,
                2 => kCreatureMaxLevel,
                _ => null,
              },
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _glassSeg(
            ['Value', 'Per level'],
            _barsShowGrowth ? 1 : 0,
            (i) => setState(() => _barsShowGrowth = i == 1),
          ),
        ),
      ],
    );
    // NO SCROLLING (user 2026-09-21: "die Werte sollen ohne Scrollen Platz
    // haben"): the two switches in one row on top, then Combat and Expedition
    // in one column and Work in the other. Combat and Expedition TOGETHER are
    // exactly as tall as Work ("genau gleich hoch wie Work"): each column is a
    // stack of panels that share its height, so both end on the same line.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        controls,
        const SizedBox(height: 9),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    group('Combat', kCombatStats),
                    const SizedBox(height: 9),
                    group('Expedition', _expeditionStats),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [group('Work', kCivilianStats)],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// A segmented switch on the glass: the live segment is white, the others
  /// are plain text. One control for every "show it this way" choice on the
  /// Stats tab.
  Widget _glassSeg(
    List<String> labels,
    int selected,
    ValueChanged<int> onSelected,
  ) => Container(
    height: 28,
    padding: const EdgeInsets.all(2),
    decoration: ShapeDecoration(
      color: _vox ? Voxel.tone(_elem, 0) : const Color(0x33000000),
      shape: _sh(radius: 14),
    ),
    child: Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Pressable(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelected(i),
              child: Container(
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: i == selected ? Colors.white : Colors.transparent,
                  shape: _sh(radius: 12),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    labels[i],
                    maxLines: 1,
                    style: TextStyle(
                      color: i == selected ? CreamPalette.ink : _inkDim,
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  /// EVOLUTION on ONE card that takes the whole width and height of the tab (user
  /// 2026-09-21: "Evolution soll die gesamte Breite und Höhe ausnutzen"): the
  /// three forms as large as the room allows, with the Evolve button underneath.
  Widget _evolutionBody(CreatureInstance creature) {
    final species = creature.species;
    if (species == null) return const SizedBox();
    final isFinal = creature.stage >= 2;
    final reqLevel = isFinal ? 0 : species.evoLevelFrom(creature.stage);
    final levelOk = creature.level >= reqLevel;
    // The level is the only requirement (user 2026-07-26). The second gate — a
    // path-earned evolution feature — is gone, and with it the "Locked" state
    // that never said what it was locked on.
    final ready = levelOk && !_evolving && !_isPreview;
    return _recess(
      radius: 14,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _panelTitle('Line'),
          const SizedBox(height: 8),
          // The full 3-stage line: reached stages in full art, the ones to come
          // as pale silhouettes (user 2026-07-18).
          Expanded(child: _evoChain(species, creature)),
          // Final form shows nothing here (user 2026-08-28: "Final form — fully
          // evolved löschen"): the line already says a creature has reached its
          // last stage. Otherwise just the button — greyed until the creature can
          // evolve, with no level number or requirement list (user 2026-07-18).
          if (!isFinal) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    ready
                        ? 'It is ready to evolve.'
                        : 'It is not ready to evolve yet — keep levelling.',
                    style: const TextStyle(
                      color: _inkDim,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // The ready-to-evolve signal is the Evolution TAB's own badge
                // now (user 2026-09-29: the arrow on this button was removed
                // again — one live indicator, not two saying the same thing
                // right next to each other on the same open tab).
                SizedBox(
                  width: 240,
                  child: _pillBtn(
                    _evolving
                        ? 'Evolving…'
                        : ready
                        ? '✨ Evolve'
                        : 'Level too low',
                    CreamPalette.gold,
                    filled: true,
                    ink: CreamPalette.ink,
                    onTap: ready ? () => _evolve(creature) : null,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // The evolution line, stage 0 → 1 → 2. A stage you have SEEN shows its real art;
  // one you have not is BLACKED OUT, exactly like the Bestiary (user 2026-09-21:
  // "Evolutionsstufen sind ausgeschwärzt wie beim Bestiary, solange ich das
  // Monster noch nicht entdeckt habe"). Seen = your best of the species has
  // reached it — the Bestiary's own rule — or it is the form in front of you now
  // (a wild one you are sizing up). The current form sits on a light plate; the
  // arrows are centred to the art (user 2026-07-18).
  Widget _evoChain(SpeciesDef species, CreatureInstance creature) {
    var bestOwned = -1;
    for (final c in _ctrl.creatures) {
      if (c.speciesId == creature.speciesId && c.stage > bestOwned) {
        bestOwned = c.stage;
      }
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var s = 0; s < 3; s++) ...[
          Expanded(
            child: _evoNode(
              species.stageAt(s),
              revealed: s <= bestOwned || s == creature.stage,
              current: s == creature.stage,
            ),
          ),
          if (s < 2)
            const Center(
              child: PixelIcon(Icons.chevron_right, color: _inkDim, size: 40),
            ),
        ],
      ],
    );
  }

  Widget _evoNode(
    SpeciesStage stage, {
    required bool revealed,
    required bool current,
  }) {
    final url = stage.imageUrl;
    final dim = revealed ? _inkDim : const Color(0x59FFFFFF);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: current
          ? ShapeDecoration(
              color: const Color(0x1FFFFFFF),
              shape: _sh(
                radius: 14,
                side: const BorderSide(color: Color(0x40FFFFFF)),
              ),
            )
          : null,
      child: Column(
        children: [
          Expanded(
            child: url == null
                ? Center(child: PixelIcon(Icons.pets, color: dim, size: 60))
                : LayoutBuilder(
                    builder: (context, cons) {
                      // Same disk-cached loader as [_art] — see the comment
                      // there for why a bare Image.network on a brand-new URL is
                      // what produced the black starter-preview art.
                      final img = CreatureSprite(
                        url: url,
                        fit: BoxFit.contain,
                        width: cons.maxWidth,
                        height: cons.maxHeight,
                        fallback: Center(
                          child: PixelIcon(Icons.pets, color: dim, size: 60),
                        ),
                      );
                      // Not seen yet → every opaque pixel flat dark, so only the
                      // shape shows: the Bestiary's own silhouette.
                      return revealed
                          ? img
                          : ColorFiltered(
                              colorFilter: const ColorFilter.mode(
                                Color(0x99000000),
                                BlendMode.srcIn,
                              ),
                              child: img,
                            );
                    },
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            revealed ? stage.name : '???',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: revealed ? _ink : _inkDim,
              fontSize: 14,
              fontWeight: current ? FontWeight.w400 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  static const _attackId = 'attack';

  /// The equipped ids that fill slots 1..5: known to the catalog, never Attack
  /// itself, and no more than [kMaxEquippedAbilities] (an old save may still hold
  /// six). Slot n is `ids[n - 1]`, so display and edits must both go through this.
  List<String> _slotIds(CreatureInstance creature) => [
    for (final id in creature.equippedAbilityIds)
      if (id != _attackId && kAbilityDefs.containsKey(id)) id,
  ].take(kMaxEquippedAbilities).toList();

  /// ABILITIES as six SLOTS (user 2026-09-21: "links und rechts je 3 übereinander
  /// für das Maximum von 6 Fähigkeiten, Attacke ist auch eine davon"). Slot 0 is
  /// Attack — free, universal, always in the fight, so it cannot be swapped — and
  /// slots 1..5 are what the monster has equipped. Tap a slot to swap its ability
  /// for another learned one; an empty slot is a "+" field.
  Widget _abilityBody(CreatureInstance creature) {
    final ids = _slotIds(creature);
    final slots = <AbilityDef?>[
      kAbilityDefs[_attackId],
      for (var i = 0; i < kMaxEquippedAbilities; i++)
        i < ids.length ? kAbilityDefs[ids[i]] : null,
    ];
    const perColumn = kMaxAbilitiesTotal ~/ 2;
    Widget column(int from) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = from; i < from + perColumn; i++) ...[
          if (i > from) const SizedBox(height: 9),
          Expanded(child: _abilitySlot(creature, i, slots[i])),
        ],
      ],
    );
    // Release moved to the tab rail itself, right under the Abilities tile
    // (user 2026-09-29) — see [_tabRail].
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: column(0)),
        const SizedBox(width: 10),
        Expanded(child: column(perColumn)),
      ],
    );
  }

  /// One of the six slots: the ability as a card in its own element's colour, or
  /// the "+" field of an empty slot.
  Widget _abilitySlot(CreatureInstance creature, int slot, AbilityDef? a) {
    final canEdit = !_isPreview && slot > 0;
    if (a == null) {
      // Slot 0 with no Attack in the catalog (not loaded yet) — a plain tile.
      if (slot == 0) {
        return _recess(
          radius: 14,
          child: const Center(
            child: Text(
              'Attack',
              style: TextStyle(
                color: _ink,
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        );
      }
      return Pressable(
        behavior: HitTestBehavior.opaque,
        onTap: canEdit ? () => _openSlotDialog(creature, slot, null) : null,
        child: Container(
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: const Color(0x14FFFFFF),
            shape: _sh(
              radius: 14,
              side: const BorderSide(color: Color(0x66FFFFFF), width: 1.4),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PixelIcon(Icons.add, size: 34, color: Color(0xB3FFFFFF)),
              Text(
                canEdit ? 'Add ability' : 'Empty slot',
                style: const TextStyle(color: _inkDim, fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }
    return _abilityCard(
      a,
      icon: slot == 0
          ? Icons.lock_outline
          : canEdit
          ? Icons.swap_horiz
          : Icons.info_outline,
      onTap: () => _openSlotDialog(creature, slot, a),
    );
  }

  /// One ability as a card in its element's colour (a self-buff in violet): name,
  /// AP, kind and power, its text. The corner icon says what a tap does — swap it,
  /// look at it, or (Attack) that it is fixed.
  Widget _abilityCard(
    AbilityDef a, {
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final base = a.kind == AbilityKind.buff
        ? const Color(0xFF7A6A9C)
        : a.element.color;
    const white = Colors.white;
    return Pressable(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(11, 8, 9, 7),
        decoration: ShapeDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(base, Colors.white, 0.08)!,
              Color.lerp(base, Colors.black, 0.5)!,
            ],
          ),
          shape: _sh(
            radius: 14,
            side: const BorderSide(color: Color(0x33FFFFFF)),
          ),
          shadows: const [
            BoxShadow(color: Color(0x47000000), offset: Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(a.element.emoji, style: const TextStyle(fontSize: 15)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    a.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: white,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 1,
                  ),
                  decoration: ShapeDecoration(
                    color: const Color(0x59000000),
                    shape: _sh(radius: 9),
                  ),
                  child: Text(
                    '${CombatEngine.abilityApCost(a)} AP',
                    style: const TextStyle(
                      color: white,
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                PixelIcon(icon, size: 16, color: const Color(0xCCFFFFFF)),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              _kindLine(a),
              style: const TextStyle(color: Color(0xE6FFFFFF), fontSize: 12),
            ),
            if (a.description.isNotEmpty)
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    shortAbilityDescription(a.description),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xEBFFFFFF),
                      fontSize: 12,
                      height: 1.25,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _kindLine(AbilityDef a) => a.kind == AbilityKind.buff
      ? a.kind.label
      : '${a.kind.label} · Power ${a.power}';

  /// What an ability's effects do, one line each, in the same words the
  /// battle-prep long-press sheet uses (user 2026-09-08).
  List<String> _effectTexts(AbilityDef a) => abilityNotes(a);

  /// THE SWAP DIALOG. A filled slot shows what the ability does in full and the
  /// other abilities the monster has learned; tap one to put it in this slot. An
  /// empty slot shows the same list to fill it. A preview (not owned) only shows
  /// the details.
  Future<void> _openSlotDialog(
    CreatureInstance creature,
    int slot,
    AbilityDef? current,
  ) {
    final canEdit = !_isPreview && slot > 0;
    final taken = creature.equippedAbilityIds.toSet();
    final candidates = <AbilityDef>[];
    if (canEdit) {
      for (final id in creature.learnedAbilityIds) {
        final def = kAbilityDefs[id];
        if (def == null || id == _attackId || taken.contains(id)) continue;
        if (creature.stage < def.unlockStage) continue;
        candidates.add(def);
      }
    }
    candidates.sort((a, b) {
      final byPower = b.power.compareTo(a.power);
      return byPower != 0 ? byPower : a.name.compareTo(b.name);
    });
    final effects = current == null ? const <String>[] : _effectTexts(current);
    return showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: CreamPalette.paperTop,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: _sh(radius: 14, side: BorderSide(color: CreamPalette.tan)),
        child: Stack(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      current?.name ?? 'Add an ability',
                      style: FoE.title(size: 16).copyWith(color: _dlgInk),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 236,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: SingleChildScrollView(
                              child: current == null
                                  ? Text(
                                      candidates.isEmpty
                                          ? 'This slot is empty. It has nothing '
                                                'else learned yet.'
                                          : 'This slot is empty. Pick one of the '
                                                'abilities it has learned.',
                                      style: FoE.label(
                                        size: 12.5,
                                      ).copyWith(color: _dlgDim),
                                    )
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${current.element.emoji} '
                                          '${_kindLine(current)} · '
                                          '${CombatEngine.abilityApCost(current)} AP',
                                          style: FoE.label(size: 12.5).copyWith(
                                            color: _dlgInk,
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                        if (current.description.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            shortAbilityDescription(
                                              current.description,
                                            ),
                                            style: FoE.label(
                                              size: 12.5,
                                            ).copyWith(color: _dlgInk),
                                          ),
                                        ],
                                        for (final line in effects)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 6,
                                            ),
                                            child: Text(
                                              line,
                                              style: FoE.label(
                                                size: 12,
                                              ).copyWith(color: _dlgDim),
                                            ),
                                          ),
                                        if (slot == 0)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 8,
                                            ),
                                            child: Text(
                                              'Attack is always in the fight and '
                                              'cannot be swapped.',
                                              style: FoE.label(
                                                size: 12,
                                              ).copyWith(color: _dlgDim),
                                            ),
                                          ),
                                      ],
                                    ),
                            ),
                          ),
                          if (canEdit) ...[
                            const SizedBox(width: 14),
                            Expanded(
                              flex: 6,
                              child: candidates.isEmpty
                                  ? Text(
                                      'Nothing else learned yet.',
                                      style: FoE.label(
                                        size: 12.5,
                                      ).copyWith(color: _dlgDim),
                                    )
                                  : ListView(
                                      padding: EdgeInsets.zero,
                                      children: [
                                        for (final c in candidates)
                                          _candidateTile(
                                            ctx,
                                            creature,
                                            slot,
                                            c,
                                          ),
                                      ],
                                    ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (canEdit && current != null)
                          TextButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _setSlot(creature, slot, null);
                            },
                            child: Text(
                              'Empty this slot',
                              style: FoE.dim(size: 13).copyWith(
                                color: CreamPalette.warn,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                        const Spacer(),
                        if (canEdit && _hasCombatSchool)
                          TextButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _openCombatSchool();
                            },
                            child: Text(
                              '📖 Learn new abilities',
                              style: FoE.label(size: 13).copyWith(
                                color: CreamPalette.accent,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // The kit's one leaving button, top right (user 2026-09-22).
            const Positioned(top: 8, right: 8, child: KitCloseButton()),
          ],
        ),
      ),
    );
  }

  /// One learned ability in the swap dialog's list.
  Widget _candidateTile(
    BuildContext ctx,
    CreatureInstance creature,
    int slot,
    AbilityDef a,
  ) {
    final base = a.kind == AbilityKind.buff
        ? const Color(0xFF7A6A9C)
        : a.element.color;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Pressable(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Navigator.pop(ctx);
          _setSlot(creature, slot, a.id);
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
          decoration: ShapeDecoration(
            color: base.withValues(alpha: 0.14),
            shape: _sh(
              radius: 10,
              side: BorderSide(color: base.withValues(alpha: 0.7), width: 1.4),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a.element.emoji, style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FoE.label(
                        size: 13,
                      ).copyWith(color: _dlgInk, fontWeight: FontWeight.w400),
                    ),
                    Text(
                      '${_kindLine(a)} · ${CombatEngine.abilityApCost(a)} AP',
                      style: FoE.dim(size: 11).copyWith(color: _dlgDim),
                    ),
                    if (a.description.isNotEmpty)
                      Text(
                        shortAbilityDescription(a.description),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: FoE.dim(size: 11).copyWith(color: _dlgDim),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Puts [abilityId] into [slot] (1..5), or empties the slot when it is null.
  /// The equipped list has no holes, so an empty slot is always past its end and
  /// emptying one pulls the ones after it up.
  Future<void> _setSlot(
    CreatureInstance creature,
    int slot,
    String? abilityId,
  ) async {
    final next = _slotIds(creature);
    final at = slot - 1;
    if (abilityId == null) {
      if (at < next.length) next.removeAt(at);
    } else if (at < next.length) {
      next[at] = abilityId;
    } else {
      next.add(abilityId);
    }
    await _ctrl.setEquipped(creature, next);
    if (mounted) setState(() {});
  }

  /// Whether a finished Combat School stands in the settlement — where a move
  /// is actually learned (user 2026-09-05).
  bool get _hasCombatSchool => _settlement.buildings.any(
    (b) => b.buildingTypeId == kCombatSchoolBuildingId && b.isComplete,
  );

  void _openCombatSchool() => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const CombatSchoolScreen()));

  /// The Abilities tab's way to the Combat School, beside the name.
  Widget _learnPill() => Pressable(
    behavior: HitTestBehavior.opaque,
    onTap: _openCombatSchool,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: ShapeDecoration(
        color: CreamPalette.gold,
        shape: _sh(radius: 12),
      ),
      child: const Text(
        '📖 Learn new',
        style: TextStyle(
          color: CreamPalette.ink,
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
      ),
    ),
  );

  // ── Shared white-theme widgets ────────────────────────────
  Widget _barRow(
    String label,
    String value,
    double frac,
    Color color, {
    double bottomPad = 12,
  }) => Padding(
    padding: EdgeInsets.only(bottom: bottomPad),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: _inkDim,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                color: _ink,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        _vox
            ? VoxelBar(value: frac, color: color, height: 12)
            : RecessBar(value: frac, color: color, height: 12),
      ],
    ),
  );

  Widget _pillBtn(
    String label,
    Color color, {
    required bool filled,
    Color ink = Colors.white,
    VoidCallback? onTap,
  }) => SizedBox(
    width: double.infinity,
    child: Pressable(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: filled ? color : Colors.transparent,
            shape: _sh(radius: 15, side: BorderSide(color: color, width: 1.6)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: filled ? ink : color,
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ),
    ),
  );

  Widget _healingInline(CreatureInstance creature, Color element) {
    final left = creature.healingRemaining;
    final cost = _ctrl.healSkipCost(creature);
    final canPay = _settlement.gold >= cost;
    return Row(
      children: [
        const Text('🩹', style: TextStyle(fontSize: 18)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'In treatment · ${_fmt(left)} left',
            style: const TextStyle(color: _inkDim, fontSize: 12),
          ),
        ),
        Pressable(
          onTap: canPay
              ? () async {
                  await _ctrl.skipHealWithGold(creature);
                  if (!mounted) return;
                }
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: ShapeDecoration(
              color: canPay ? element : _track,
              shape: _sh(radius: 12),
            ),
            child: Text(
              '🪙 $cost',
              style: TextStyle(
                color: canPay ? Colors.white : _inkDim,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// This item's resulting HP if used now — the RIGHT unit to compare heal
  /// and revive items on (they express their strength differently: a heal
  /// item in flat HP capped at what's missing, a revive item as a fraction
  /// of max HP).
  double _healResult(ItemDef d, CreatureInstance creature, int missing) =>
      d.kind == ItemKind.revive
      ? creature.maxHp * d.magnitude
      : creature.hp + healFromItem(d, missing.toDouble());

  Widget _potionInline(CreatureInstance creature, Color element) {
    final missing = creature.maxHp - creature.hp;
    final ko = creature.isKo;
    // Heal items when hurt, revive items when K.O. — exactly what useItemOn
    // would accept, so no chip taps into a "can't use that" error.
    final held = [
      for (final e in _settlement.items.entries)
        if (kItemDefs[e.key] case final ItemDef d
            when (d.kind == ItemKind.heal && missing > 0) ||
                (d.kind == ItemKind.revive && ko))
          (d, e.value),
    ];
    if (held.isEmpty) return const SizedBox.shrink();
    // The ONE potion closest to topping the creature off (user 2026-08-28:
    // "Use an item - missing n hp löschen. Dafür automatisch den Trank
    // anzeigen, welcher am nächsten an die max. HP auffüllt") — replaces
    // the old caption + pick-one-of-several row. Ties (several potions
    // that all fully heal) break toward the SMALLEST of them, so a big
    // potion isn't spent on a wound a small one already covers.
    final sorted = [...held]
      ..sort((a, b) {
        final gapA = (creature.maxHp - _healResult(a.$1, creature, missing))
            .abs();
        final gapB = (creature.maxHp - _healResult(b.$1, creature, missing))
            .abs();
        final byGap = gapA.compareTo(gapB);
        if (byGap != 0) return byGap;
        final costA = a.$1.kind == ItemKind.revive
            ? a.$1.magnitude
            : a.$1.healHp;
        final costB = b.$1.kind == ItemKind.revive
            ? b.$1.magnitude
            : b.$1.healHp;
        return costA.compareTo(costB);
      });
    final (def, count) = sorted.first;
    // Back to the LEFT (user 2026-08-29: "tausche es wieder: use item
    // button links") — the right-align from earlier that day is undone.
    return Pressable(
      onTap: () => _usePotion(def, creature),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: ShapeDecoration(color: element, shape: _sh(radius: 12)),
        // "(N)" for how many are in storage now, not "×N" (user 2026-08-29:
        // "Anzahl nicht xn sondern die Anzahl im Lager befindlichen als (n)
        // schreiben") — [count] already IS the stored amount ([_settlement]
        // .items), only the format changes.
        child: Text(
          def.kind == ItemKind.revive
              ? '${def.emoji} ${def.name} ($count) · → '
                    '${_healResult(def, creature, missing).round()} HP'
              : '${def.emoji} ${def.name} ($count) · '
                    '+${healFromItem(def, missing.toDouble()).round()} HP',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }

  /// WHERE the monster works, if anywhere (user 2026-08-28: "Workbox
  /// einführen: wo arbeitet das Monster"), the BUILDING'S OWN icon instead
  /// of a generic glyph (same day: "Icon löschen dafür das Haus Icon
  /// hinzufügen"), and the rate/ETA the old Condition box's caption used to
  /// carry, back but living HERE (same day: "Ep pro Stunde hinzufügen und
  /// wie lange es geht, bis das nächste Level erreicht wird").
  Widget _workPanel(CreatureInstance creature, {double gap = 0}) {
    final id = creature.assignedBuildingId;
    final buildings = SettlementController().buildings;
    final idx = id == null ? -1 : buildings.indexWhere((b) => b.id == id);
    if (idx < 0) {
      return _fillPanel(
        header: _panelTitle('Work'),
        gap: gap,
        child: const Text(
          '💤 Not stationed anywhere.',
          style: TextStyle(color: _inkDim, fontSize: 12),
        ),
      );
    }
    final building = buildings[idx];
    final name =
        kBuildingDefs[building.buildingTypeId]?.name ?? building.buildingTypeId;
    final atMax = creature.level >= kCreatureMaxLevel;
    final rate = CreaturesController().xpRatePerHour(creature);
    // Every building with a work post pays the same work rate since
    // 2026-07-30, so a zero here means the rate itself is dialled to
    // nothing — say so instead of dividing by zero into "∞ to Lv N".
    String? rateXpLine;
    String? etaLine;
    if (!atMax) {
      if (rate <= 0) {
        rateXpLine = 'Work rate is set to zero — no XP here right now.';
      } else {
        rateXpLine = '+${rate.toStringAsFixed(0)} XP/h';
        // Its OWN line under the rate now (user 2026-08-28: "nd to lv n.
        // eine Zeile unter der xp/h Anzeige").
        etaLine =
            '~${_fmtDays((xpToNextLevel(creature.level) - creature.xp) / rate)}'
            ' to Lv ${creature.level + 1}.';
      }
    }
    return _fillPanel(
      header: _panelTitle('Work'),
      gap: gap,
      // The panel is as tall as the column it sits in (General puts it above
      // Strengths, and the two columns are the same height — user 2026-09-21),
      // so the building's picture is sized to the room there is instead of a
      // fixed 185 px.
      child: LayoutBuilder(
        builder: (context, cons) {
          final iconW = (cons.maxHeight * 1.1).clamp(90.0, 170.0);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: EdgeInsets.only(right: iconW * 0.62),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // White, not the dim ink (user 2026-08-29): the only line
                    // in the box worth making stand out.
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    if (rateXpLine != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        rateXpLine,
                        style: const TextStyle(color: _inkDim, fontSize: 11),
                      ),
                    ],
                    if (etaLine != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        etaLine,
                        style: const TextStyle(color: _inkDim, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
              // [ShadowedBuildingIcon] — the exact widget the build-menu cards
              // and the map's building-detail dialog use. Bottom-anchored ONLY
              // (no `top`) is what makes it rise past its own slot.
              Positioned(
                right: -8,
                bottom: -4,
                child: ShadowedBuildingIcon(
                  imageUrl: null,
                  defId: building.buildingTypeId,
                  width: iconW,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _fmt(Duration d) =>
      d.inHours > 0 ? '${d.inHours}h ${d.inMinutes % 60}m' : '${d.inMinutes}m';

  static String _fmtDays(double hours) {
    if (hours < 1) return '${(hours * 60).round()}m';
    if (hours < 48) return '${hours.round()}h';
    return '${(hours / 24).round()}d';
  }
}
