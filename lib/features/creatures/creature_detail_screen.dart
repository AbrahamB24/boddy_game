import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/foe_theme.dart';
import '../settlement/widgets/meander_strip.dart';
import '../settlement/widgets/scroll_paper.dart'
    show kParchmentInk, kParchmentLight, kParchmentMid;
import '../common/widgets/app_back_button.dart';
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
import 'widgets/creature_backdrop.dart';
import 'widgets/creature_sprite.dart';
import 'widgets/gene_bar_toggle.dart';
import 'widgets/xp_arc.dart';
import 'services/creature_power.dart';
import 'services/creatures_controller.dart';
import '../common/widgets/recess_bar.dart';
import '../../core/ui/pressable.dart';

/// The Abilities tab's own sort keys (user 2026-09-06). Equipped abilities
/// always float to the top regardless of which of these is active — see
/// [_CreatureDetailScreenState._sortedCurriculum].
enum _AbilitySort {
  stage('Unlock order'),
  power('Power'),
  apCost('AP cost'),
  name('Name');

  final String label;
  const _AbilitySort(this.label);
}

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

  /// The Abilities tab's own sort key (user 2026-09-06: "sortierfunktion
  /// hinzufügen") — equipped abilities float to the top regardless of which
  /// of these is picked; see [_sortedCurriculum].
  _AbilitySort _abilitySort = _AbilitySort.stage;

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

  /// Ability ids currently expanded in the Abilities tab (user 2026-09-08:
  /// "Buffs und Debuffs besser erklären, damit ich genau weiss, was diese
  /// machen") — tap a row to see exactly what its effects do, in the same
  /// words the battle-prep long-press sheet already uses.
  final Set<String> _expandedAbilityIds = {};

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
                      color: _paper(element, 0.14),
                      shape: FoE.facet(
                        radius: 10,
                        side: BorderSide(color: element.withValues(alpha: 0.5)),
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
                            fontWeight: FontWeight.w700,
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

  /// The page in [element]'s hue at a fixed [lightness] — the higher value at
  /// the top of the sheet, the lower at its foot.
  ///
  /// DARK since the app is (2026-07-31): the lightnesses the callers pass moved
  /// from 0.90/0.80 to 0.16/0.10, and everything else about the rule is
  /// unchanged. That is the point of fixing lightness here rather than blending
  /// the raw element colour into the page — the tint follows the theme by
  /// changing two numbers, and the ink over it stays legible by construction.
  ///
  /// A near-grey element keeps the plain page: pushing saturation into something
  /// that has none invents a colour the monster does not have.
  static Color _paper(Color element, double lightness) {
    final hsl = HSLColor.fromColor(element);
    if (hsl.saturation < 0.08) {
      return Color.lerp(kParchmentLight, kParchmentMid, 1 - lightness / 0.16)!;
    }
    return hsl
        .withSaturation(hsl.saturation.clamp(0.22, 0.48))
        .withLightness(lightness)
        .toColor();
  }

  static const _ink = kParchmentInk; // primary text
  // Literal ARGB rather than withValues: these are used in `const` widgets all
  // over this file, and a computed colour is not a constant.
  static const _inkDim = Color(0x94EDE3CB); // ink @ 58 %
  // Bar / chip fill. A RECESS on the light sheet — it used to be the lightest
  // tone in the palette, which on parchment made every track brighter than the
  // paper around it.
  static const _track = Color(0x21EDE3CB); // ink @ 13 %

  /// Ornament ink for the meander bordure — the page's own shade.
  static const _ornament = Color(0x38EDE3CB); // ink @ 22 %

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
      _isPreview && !_ctrl.creatures.any((c) => c.speciesId == creature.speciesId);

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
    // No pop-up confirmation any more (user 2026-08-29: "bitte wirklich alle
    // pop up nachrichten... löschen") — the screen's own state already shows
    // the result (the new stage's art/name), so this was a message about
    // something already visible.
    await _ctrl.evolve(creature);
    if (!mounted) return;
    setState(() => _evolving = false);
  }

  // Rename dialog, styled to match this screen (dark sheet, Outfit font, the
  // creature's element as the accent) rather than the global FoE gold theme
  // (user 2026-07-18).
  Future<void> _devEvolve(CreatureInstance creature) async {
    final err = await _ctrl.devEvolve(creature);
    if (!mounted) return;
    if (err != null) {
      context.snack(err, error: true);
    } else {
      setState(() {});
      final name =
          creature.species?.stageAt(creature.stage).name ?? 'its next form';
      context.snack('🛠 Evolved to $name (Lv ${creature.level})');
    }
  }

  Future<void> _rename(CreatureInstance creature) async {
    final element = creature.species?.element.color ?? FoE.gold;
    final controller = TextEditingController(text: creature.nickname ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _paper(element, 0.16),
        shape: FoE.facet(radius: 20),
        title: Text(
          'Rename',
          style: GoogleFonts.outfit(
            color: _ink,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          cursorColor: element,
          style: GoogleFonts.outfit(color: _ink, fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Empty = species name',
            hintStyle: GoogleFonts.outfit(color: _inkDim, fontSize: 13),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: _track),
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
                color: _inkDim,
                fontSize: 14,
                fontWeight: FontWeight.w600,
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
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    if (name != null) await _ctrl.rename(creature, name);
  }

  Future<void> _release(CreatureInstance creature) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FoE.panelDark,
        shape: FoE.facet(
          radius: 12,
          side: const BorderSide(color: FoE.borderGold),
        ),
        title: Text('Release?', style: FoE.title(size: 15)),
        content: Text(
          '${creature.displayName} leaves you forever.',
          style: FoE.label(size: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: FoE.dim(size: 13)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Release',
              style: FoE.label(size: 13).copyWith(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      final error = await _ctrl.release(creature);
      if (!mounted) return;
      // No pop-up on failure any more (user 2026-08-29: "wirklich alle pop
      // up nachrichten... löschen") — the dialog simply doesn't proceed;
      // staying on this screen with nothing released IS the signal.
      if (error != null) return;
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
  @override
  Widget build(BuildContext context) {
    // The scaffold under the sheet takes the same tint — an overscroll bounce
    // that revealed beige would say the page was two pages.
    final scaffoldElement = _creature?.species?.element.color ?? FoE.gold;
    return Scaffold(
      backgroundColor: _paper(scaffoldElement, 0.10),
      body: ListenableBuilder(
        listenable: Listenable.merge([_ctrl, _settlement]),
        builder: (context, _) {
          final creature = _creature;
          if (creature == null) {
            return Center(
              child: Text('Creature not found', style: FoE.label()),
            );
          }
          final species = creature.species;
          final element = species?.element.color ?? FoE.gold;
          return SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, c) {
                final h = c.maxHeight;
                final sheetTop = h * 0.30;
                final imgTop = h * 0.03;
                final imgH =
                    h * 0.35; // spans imgTop..imgTop+imgH, over the seam
                final contentTop = (imgTop + imgH) - sheetTop - 30;
                return Stack(
                  children: [
                    // Element backdrop — the SAME as the Monsters-menu tile.
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: sheetTop + 40,
                      child: species == null
                          ? Container(color: element)
                          : CreatureBackdrop(
                              element: species.element,
                              radius: 0,
                              child: const SizedBox.expand(),
                            ),
                    ),
                    // The sheet — rounded top, holds everything below the art,
                    // and printed in this monster's own colour (2026-07-31).
                    Positioned(
                      top: sheetTop,
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              _paper(element, 0.16),
                              _paper(element, 0.10),
                            ],
                          ),
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(30),
                          ),
                        ),
                        // The bordure, on the sheet only — it is the page's
                        // printed border, and the page here starts where the
                        // element backdrop ends. It runs the sheet's FULL
                        // height, right up to its rounded top edge (user
                        // 2026-08-31: "soll auch hier bis ganz oben von dem
                        // dunklen Balken gehen und quasi durch die Rundung
                        // abgeschnitten werden") — the Container's own
                        // Clip.antiAlias does the cutting; only the CONTENT
                        // keeps the top padding that clears the art/seam.
                        child: Stack(
                          children: [
                            Positioned(
                              left: 14,
                              top: 0,
                              bottom: 0,
                              width: 16,
                              child: MeanderStrip(
                                color: _ornament,
                                fillHeight: true,
                              ),
                            ),
                            Positioned(
                              right: 14,
                              top: 0,
                              bottom: 0,
                              width: 16,
                              child: MeanderStrip(
                                color: _ornament,
                                flip: true,
                                fillHeight: true,
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.only(top: contentTop),
                              child: _sheet(creature, species, element),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Monster art, straddling the backdrop and the white sheet.
                    Positioned(
                      top: imgTop,
                      left: 0,
                      right: 0,
                      height: imgH,
                      // Clip the shadow to where the coloured backdrop is
                      // actually VISIBLE (in art-local coords): the dark sheet
                      // is drawn over the backdrop from sheetTop down, so the
                      // shadow must end at sheetTop — no shadow on the dark
                      // sheet below (user request).
                      child: IgnorePointer(
                        child: _art(
                          creature,
                          backdropBottom: sheetTop - imgTop,
                          displayHeight: imgH,
                        ),
                      ),
                    ),
                    // Controls over the backdrop: back button (left) and Power
                    // (right) on ONE row so they sit at the same height (user
                    // 2026-07-18). Power is just the ⚡ icon + number, no label.
                    Positioned(
                      top: 8,
                      left: 4,
                      right: 14,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          AppBackButton(
                            color: Colors.white,
                            onTap: () => Navigator.of(context).pop(),
                          ),
                          const Spacer(),
                          // Power (⚡ + number) with the rarity in its own colour
                          // right below it (user 2026-07-18).
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    '⚡',
                                    style: TextStyle(fontSize: 28),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${totalPower(creature)}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 30,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                              if (species != null)
                                Text(
                                  species.rarity.label,
                                  style: TextStyle(
                                    color: species.rarity.color,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _art(
    CreatureInstance creature, {
    required double backdropBottom,
    required double displayHeight,
  }) {
    final url = creature.imageUrl;
    if (url == null) {
      return const Icon(Icons.pets, color: Colors.white70, size: 90);
    }
    // The drop shadow uses the element's own shadow tone — the same colour its
    // type icon is embossed with (user request).
    final shadowColor =
        (creature.species?.element ?? CreatureElement.fire).shadowColor;
    // Routed through the SAME loader every other screen uses for creature
    // art (user 2026-09-02) — this used to be a bare Image.network, which is
    // exactly what CreatureSprite itself now falls back to on Flutter Web
    // (see its own doc comment) after the starter preview's art turned out
    // to load unreliably there via CachedNetworkImage. Fixing that inside
    // CreatureSprite covers every screen at once rather than special-casing
    // it here.
    Widget image() => CreatureSprite(
      url: url,
      fit: BoxFit.contain,
      // Decode at DISPLAY size, not native (user 2026-08-29: "die
      // Monsterassets werden sehr langsam geladen").
      height: displayHeight,
      fallback: const Icon(Icons.pets, color: Colors.white70, size: 90),
    );
    // 20% bigger, CENTRED again (user 2026-08-28: "Nein das Monster wieder
    // auf die Position setzen wie vorher, aber den Schatten neu
    // kalibrieren") — back to matching [CreatureCard]'s own fix, with the
    // shadow's clip line recalibrated instead of giving up the centring.
    const scale = 1.20;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Centring this Transform.scale maps every LOCAL y toward
        // `center + (y - center) * scale`. The shadow's clip line is drawn
        // in this same local space (see _TopRectClipper) and gets mapped by
        // that SAME formula once the scale is applied around it — so
        // without correction it lands at the wrong absolute y and the
        // shadow bleeds onto the dark sheet below (user 2026-08-28: "der
        // Schatten ... ragt in den dunklen Bereich"). Solving that formula
        // for the LOCAL y that maps back to the true, fixed sheet boundary
        // is this line — the inverse of the map the Transform.scale below
        // applies.
        final center = constraints.maxHeight / 2;
        final adjustedClip = center + (backdropBottom - center) / scale;
        return Transform.scale(
          scale: scale,
          alignment: Alignment.center,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Drop shadow behind the monster: the sprite's SHARP
              // silhouette in the element's shadow tone, a bit SMALLER than
              // the sprite and clipped to the coloured backdrop — so there
              // is NO shadow on the dark sheet below (user request).
              Positioned.fill(
                child: ClipRect(
                  clipper: _TopRectClipper(adjustedClip),
                  child: Transform.translate(
                    offset: const Offset(2, 8),
                    child: Transform.scale(
                      scale: 0.9,
                      alignment: Alignment.bottomCenter,
                      child: ColorFiltered(
                        colorFilter: ColorFilter.mode(
                          shadowColor,
                          BlendMode.srcATop,
                        ),
                        child: image(),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(child: image()),
            ],
          ),
        );
      },
    );
  }

  Widget _sheet(CreatureInstance creature, SpeciesDef? species, Color element) {
    final desc = species?.description ?? '';
    final atMax = creature.level >= kCreatureMaxLevel;
    final need = atMax ? 1 : xpToNextLevel(creature.level);
    final xpFrac = atMax ? 1.0 : (creature.xp / need).clamp(0.0, 1.0);
    // Outfit for everything on the sheet: these Text widgets set colour/size but
    // no fontFamily, so merging the game font in here flows through to all of
    // them (and the tab bodies) without touching each style.
    return DefaultTextStyle.merge(
      style: GoogleFonts.outfit(),
      child: Padding(
        // CLEAR OF THE BORDURE (user 2026-07-29: "alles etwas weiter nach innen
        // schieben, damit es nicht so nahe an der Dekoration ist"). The meander
        // bands sit at 14 and run 16 wide (widened 2026-09-06 to match
        // building_detail_dialog.dart; were 4/14), so they end at exactly 30 —
        // 40 leaves the same ten pixels of paper on either side that 28 gave
        // the old 18px edge; [ParchmentPage] does the same thing with its own
        // 36 against the same bands.
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          children: [
            // The arc stays exactly where it was (its 34px box pinned to the
            // bottom of this 58px region = the old 24px gap above it). The Level
            // sits in that gap, between the image and the arc; being last in the
            // Stack it draws ON TOP of the arc's raised ends if they overlap
            // (user 2026-07-18).
            SizedBox(
              width: double.infinity,
              height: 58,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 34,
                    child: _xpBase(xpFrac),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 25,
                    child: Center(
                      child: Text(
                        'Level ${creature.level}',
                        style: TextStyle(
                          color: element,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              atMax ? 'MAX' : '${creature.xp} / $need EP',
              style: const TextStyle(
                color: _inkDim,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            // Name + gender. The row is centre-aligned so the edit icon sits at
            // the name's mid-height (not raised); only the gender is lifted into
            // a superscript (user 2026-07-18).
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    creature.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Transform.translate(
                  offset: const Offset(4, -7),
                  child: Text(
                    creature.gender.symbol,
                    style: TextStyle(
                      color: creature.gender.color,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Never caught before (user 2026-09-14) — same badge shape
                // the build menu's own MAX/QUEUE FULL tag uses.
                if (_isNewSpecies(creature))
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: ShapeDecoration(
                        color: FoE.goldBright,
                        shape: FoE.facet(radius: 6),
                      ),
                      child: Text(
                        'NEW',
                        style: FoE.dim(size: 9).copyWith(
                          color: _ink,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                // Small edit (rename) button, right of the name/gender. Not
                // owned yet in preview — nothing valid to rename.
                if (!_isPreview)
                  Pressable(
                    onTap: () => _rename(creature),
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.edit, size: 16, color: _inkDim),
                    ),
                  ),
              ],
            ),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                desc,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _inkDim,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 14),
            _tabBar(element),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 24),
                child: switch (_tab) {
                  1 => _statsTab(creature, element),
                  2 => _evolutionTab(creature),
                  3 => _abilitiesTab(creature),
                  _ => _generalTab(creature, element),
                },
              ),
            ),
            // The caller's footer (the starter preview's "Choose" button) —
            // OUTSIDE the tab switch so it stays put across all four tabs
            // (user 2026-09-02: "sollte der Button auf allen 4 Reiter unten
            // sein"), unlike Release/dev, which only ever lived on General.
            if (widget.footer != null) ...[
              const SizedBox(height: 12),
              widget.footer!,
            ],
          ],
        ),
      ),
    );
  }

  // The XP bar as a wide platform under the monster's feet — an open-topped
  // arc (the monster sits in the cup). Same gold fill + leading dot as the
  // Monsters card; the greyed remainder shows how far to the next level.
  //
  // Layout height stays 34, but the arc is painted in a TALLER (57) area pinned
  // to the bottom via OverflowBox — so the arc's bottom holds its place while
  // the two ends curl higher (user 2026-07-18), without pushing the EP line
  // below it down.
  Widget _xpBase(double xpFrac) => SizedBox(
    width: double.infinity,
    height: 34,
    child: OverflowBox(
      alignment: Alignment.bottomCenter,
      maxHeight: 57,
      child: SizedBox(
        height: 57,
        child: CustomPaint(painter: XpArcPainter(xpFrac)),
      ),
    ),
  );

  /// ONE SEGMENTED CONTROL, NOT FOUR BUTTONS (user 2026-07-29: "der obere
  /// Bereich gefällt mir, aber der Untere Bereich etwas anpassen").
  ///
  /// It was four outlined pills side by side, all four drawn in the element
  /// colour — so the row read as four things you could press rather than one
  /// setting with four positions, and three unselected outlines carried as much
  /// colour as the selected one.
  ///
  /// Now it is a TRACK CUT INTO THE SHEET with one key raised in it: the groove
  /// is dark along its top edge and lit along its bottom (a recess), and the
  /// selected segment is the exact inverse (lit on top, casting below). The same
  /// two-hairline grammar the header band and the settlement's corner keys use —
  /// which is what makes "this one is pressed" legible without any colour at
  /// all.
  Widget _tabBar(Color element) {
    const labels = ['General', 'Stats', 'Evolution', 'Abilities'];
    return _recess(
      radius: 19,
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(child: _tabSegment(labels[i], i, element)),
        ],
      ),
    );
  }

  Widget _tabSegment(String label, int index, Color element) {
    final on = _tab == index;
    return Pressable(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _tab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        // The selected key is ONE plane of the element's colour (2026-07-31):
        // it used to be lit at the top and deep at the foot, which is a curve
        // pretending to be a key.
        decoration: ShapeDecoration(
          color: on ? element : Colors.transparent,
          shape: FoE.facet(radius: 15),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          // FLAT (2026-07-31): the selected key was a raised, casting button and
          // the others were letters cut into a groove. Colour alone says which
          // tab you are on — it always did, the relief was saying it a second
          // time.
          style: TextStyle(
            color: on ? Colors.white : _inkDim,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

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
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: _recess(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
      color: kParchmentInk.withValues(alpha: 0.07),
      shape: FoE.facet(
        radius: radius,
        side: BorderSide(color: kParchmentInk.withValues(alpha: 0.14)),
      ),
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
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
      ),
      if (trailing != null) trailing,
    ],
  );

  // ── Tabs ──────────────────────────────────────────────────
  Widget _generalTab(CreatureInstance creature, Color element) {
    final hpFrac = creature.maxHp > 0 ? creature.hp / creature.maxHp : 0.0;
    // Keep the HP-bar colour thresholds identical to the collection card's
    // _hpBar (2026-07-18): red is the signal for "needs attention", not only K.O.
    final hpColor = hpFrac <= 0
        ? FoE.danger
        : hpFrac < 0.3
        ? FoE.danger
        : hpFrac < 0.6
        ? FoE.gold
        : FoE.positive;
    final top = topStats(creature);
    // The Combat/Civil split bar was removed (user 2026-07-24): the split is now
    // fixed for every species (≈49:51), so the bar looked identical on every
    // monster and carried no information. Total Power still lives top-right.
    // Only healing/potion now (user 2026-08-28: "Working.... Text löschen")
    // — the passive-XP-rate caption this used to fall back to is gone; WHERE
    // a monster works has its own box below now instead of a rate here.
    final care = creature.isHealing
        ? _healingInline(creature, element)
        : creature.hp < creature.maxHp
        ? _potionInline(creature, element)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // No more "CONDITION" box or title (user 2026-08-28: "Condition Box
        // und Text löschen") — the HP bar and, when relevant, the heal/potion
        // control stay (a way to treat a hurt monster from this screen is
        // worth keeping), just not framed as a card of their own any more.
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _barRow(
                'HP',
                '${creature.hp} / ${creature.maxHp}',
                hpFrac,
                hpColor,
                bottomPad: care == null ? 0 : 12,
              ),
              if (care != null) care,
            ],
          ),
        ),
        _workPanel(creature),
        if (top.isNotEmpty)
          _panel(
            title: 'Strengths',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in top) _strengthChip(s, creature, element),
              ],
            ),
          ),
        // Not shown in preview (user 2026-09-02) — the caller's own footer
        // takes this spot instead (see [_sheet]), since Release and the dev
        // tools all assume a creature that is actually owned.
        if (!_isPreview) ...[
          // The starter never gets a Release button at all (user 2026-09-02:
          // "Das Startmonster kann aber niemals entlassen werden") — it's
          // the player's one permanent companion, not just a first pick.
          if (!creature.isStarter) ...[
            const SizedBox(height: 8),
            _pillBtn(
              'Release',
              Colors.redAccent,
              filled: false,
              onTap: () => _release(creature),
            ),
          ],
          if (_settlement.isDev) ...[
            const SizedBox(height: 8),
            _pillBtn(
              '🛠 +500 XP (Dev)',
              _inkDim,
              filled: false,
              onTap: () => _ctrl.devGainXp(creature, 500),
            ),
            // Straight to the next form: the level is raised to the threshold
            // first, so the monster that comes out is a legitimate over-levelled
            // one rather than a stage-2 body with stage-1 stats (user
            // 2026-08-01). Hidden at the final stage — there is nothing to jump
            // to, and a button that only ever refuses is worse than no button.
            if (creature.hasNextStage) ...[
              const SizedBox(height: 8),
              _pillBtn(
                '🛠 Evolve to ${creature.species?.stageAt(creature.stage + 1).name ?? 'next stage'} (Dev)',
                _inkDim,
                filled: false,
                onTap: () => _devEvolve(creature),
              ),
            ],
          ],
        ],
      ],
    );
  }

  /// One of the creature's best stats, as a chip in the element colour.
  ///
  /// They were bare coloured words in a centred wrap, which at three of them
  /// read as a sentence someone had forgotten to finish. A chip each says these
  /// are three separate facts, and puts the number where the eye expects it.
  Widget _strengthChip(
    CreatureStat stat,
    CreatureInstance creature,
    Color element,
  ) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: ShapeDecoration(
      color: element.withValues(alpha: 0.14),
      shape: FoE.facet(
        radius: 11,
        side: BorderSide(color: element.withValues(alpha: 0.5)),
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          stat.label,
          style: TextStyle(
            color: Color.lerp(element, kParchmentInk, 0.25),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '${creature.statValue(stat)}',
          style: TextStyle(
            color: Color.lerp(element, kParchmentInk, 0.25),
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );

  // The two utility stats that ride along on expeditions — carry (loot hauled)
  // and catchRate (this creature's Fangwert). Neither is a workshop role, so
  // they live in their own group rather than under Work.
  static const _expeditionStats = [CreatureStat.carry, CreatureStat.catchRate];

  Widget _statsTab(CreatureInstance creature, Color element) {
    // The Lvl-1/Max preview (user 2026-09-14) overrides which level every
    // number below is computed at — see [_refLevel]'s own doc comment.
    final atLevel = _refLevel ?? creature.level;
    final values = {
      for (final s in CreatureStat.values) s: creature.statValueAtLevel(s, atLevel),
    };
    // "Beats your best" — only meaningful once a SHARED reference level is
    // picked (comparing at each creature's own current level tells you
    // nothing, which is exactly why the toggle exists). Excludes this
    // creature itself, so viewing your own best individual doesn't just tie
    // with itself; empty when nothing else of this species is owned yet
    // (a fresh starter preview, or the very first of a species).
    // Excludes this creature itself, so viewing your own best individual
    // doesn't just tie with itself; empty when nothing else of this species
    // is owned yet (a fresh starter preview, or the very first of a
    // species).
    final ownedRivals = _ctrl.creatures.where(
      (c) => c.speciesId == creature.speciesId && c.id != creature.id,
    );
    // "Beats your best" on the VALUE — only meaningful once a SHARED
    // reference level is picked (comparing at each creature's own current
    // level tells you nothing, which is exactly why the toggle exists).
    final bestOwnedValue = {
      for (final s in CreatureStat.values)
        s: _refLevel == null
            ? null
            : bestOwnedStatAtLevel(ownedRivals, s, _refLevel!),
    };
    // "Beats your best" on the GROWTH gene (user 2026-09-14: "die pro Stufe
    // Statboni ebenfalls markieren") — this one needs NO reference level:
    // growth-per-level is already a flat rate, comparable exactly as
    // rolled, so it marks unconditionally regardless of the toggle above.
    final bestOwnedSlope = {
      for (final s in CreatureStat.values) s: bestOwnedGrowth(ownedRivals, s),
    };
    // WHICH GENE THE BARS DRAW (user 2026-07-27) — the level-up caption is a
    // switch now, the same one the breeding and Hatchery tables carry. The
    // scale follows it: a growth of +1.6 against a stat of 80 would otherwise
    // be a hairline on every row.
    final barValues = _barsShowGrowth
        ? {for (final s in CreatureStat.values) s: (creature.statSlope[s] ?? 0)}
        : {for (final s in CreatureStat.values) s: values[s]!.toDouble()};
    final maxVal = barValues.values.reduce((a, b) => a > b ? a : b);
    int totalOf(List<CreatureStat> group) =>
        group.fold(0, (sum, s) => sum + values[s]!);

    // WHICH COLUMN READS AS THE HEADLINE follows the same switch the bars do
    // (user 2026-08-31: "je nachdem was ich anwähle, ist das eine oder
    // andere Fett und gross geschrieben") — value is bold/big by default,
    // but with the toggle on GROWTH the row is read for its per-level gene,
    // so growth takes the big/bold style and the current value steps back
    // to the small/dim one instead of the two staying fixed regardless of
    // which the bars themselves are plotting.
    const bigStyle = TextStyle(
      color: _ink,
      fontSize: 12,
      fontWeight: FontWeight.w700,
    );
    const smallStyle = TextStyle(
      color: _inkDim,
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
    );
    final valueStyle = _barsShowGrowth ? smallStyle : bigStyle;
    final growthStyle = _barsShowGrowth ? bigStyle : smallStyle;

    // The group's summed value rides in its card's heading, over the value
    // column, so it lines up with the rows beneath it.
    Widget header(String label, int total) => _panelTitle(
      label,
      trailing: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '$total',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: _ink,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          // Holds the total over the VALUE column now that growth sits to its
          // right — a group's sum is a sum of values, not of growths.
          const SizedBox(width: 42),
        ],
      ),
    );

    // A stat row: label · bar · current value · growth-per-level.
    //
    // Value BEFORE growth since 2026-07-27 ("lvl 1 und level up icon sind
    // vertauscht") — the two number columns ran the other way round to the
    // switch above them, so its halves sat over the wrong columns.
    Widget row(CreatureStat stat, Color color) {
      final growth = creature.statSlope[stat] ?? 0;
      // "Beats your best" on the value — only lit once [_refLevel] picks a
      // shared level to compare at; see [bestOwnedValue]'s own comment above.
      final bestValue = bestOwnedValue[stat];
      final valueBeats = bestValue != null && values[stat]! > bestValue;
      // Same marker on the growth gene, unconditionally (see
      // [bestOwnedSlope]'s own comment above).
      final bestGrowth = bestOwnedSlope[stat];
      final growthBeats = bestGrowth != null && growth > bestGrowth;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            SizedBox(
              width: 86,
              // Tap the name for what the stat is actually used for (user
              // 2026-09-06) — see [_showStatInfo] for why this is a
              // hand-rolled popover rather than a [Tooltip].
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) =>
                    _showStatInfo(details.globalPosition, stat, color),
                child: Text(
                  stat.label,
                  style: const TextStyle(color: _ink, fontSize: 12),
                ),
              ),
            ),
            Expanded(
              child: RecessBar(
                value: maxVal > 0 ? barValues[stat]! / maxVal : 0,
                color: color,
                height: 10,
              ),
            ),
            SizedBox(
              width: 46,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (valueBeats)
                    const Padding(
                      padding: EdgeInsets.only(right: 1),
                      child: Icon(
                        Icons.arrow_drop_up,
                        size: 16,
                        color: FoE.positive,
                      ),
                    ),
                  Text(
                    '${values[stat]}',
                    textAlign: TextAlign.right,
                    style: valueBeats
                        ? valueStyle.copyWith(
                            color: FoE.positive,
                            fontWeight: FontWeight.w800,
                          )
                        : valueStyle,
                  ),
                ],
              ),
            ),
            // Growth per level (the sampled slope gene) — same "beats your
            // best" marker as the value column, see [growthBeats] above.
            SizedBox(
              width: 46,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (growthBeats)
                    const Padding(
                      padding: EdgeInsets.only(right: 1),
                      child: Icon(
                        Icons.arrow_drop_up,
                        size: 16,
                        color: FoE.positive,
                      ),
                    ),
                  Text(
                    '+${growth.toStringAsFixed(1)}',
                    textAlign: TextAlign.right,
                    style: growthBeats
                        ? growthStyle.copyWith(
                            color: FoE.positive,
                            fontWeight: FontWeight.w800,
                          )
                        : growthStyle,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // All bars in the type colour (user 2026-07-18). One CARD per group: the
    // three used to be told apart by a blank six pixels, which at thirteen rows
    // is not a separation at all.
    Widget group(String label, List<CreatureStat> stats) => _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header(label, totalOf(stats)),
          const SizedBox(height: 10),
          for (final s in stats) row(s, element),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Both switches sit ABOVE the groups, once. Inside the first card
        // either would look like a setting for Combat only.
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: _levelRefToggle(),
              ),
            ),
            GeneBarToggle(
              showGrowth: _barsShowGrowth,
              onChanged: (v) => setState(() => _barsShowGrowth = v),
              ink: _ink,
              inkFaint: _inkDim,
              accent: FoE.goldBright,
            ),
          ],
        ),
        const SizedBox(height: 8),
        group('Combat', kCombatStats),
        group('Work', kCivilianStats),
        group('Expedition', _expeditionStats),
      ],
    );
  }

  /// Lvl 1 / Max segmented control (user 2026-09-14) — same bordered-track
  /// look as [GeneBarToggle], but 2 independent toggles rather than one
  /// either/or switch: tapping the already-active segment returns to showing
  /// the creature at its own real level (both off = [_refLevel] null).
  Widget _levelRefToggle() => Container(
    height: 22,
    decoration: ShapeDecoration(
      shape: FoE.facet(
        radius: 11,
        side: BorderSide(color: _inkDim.withValues(alpha: 0.45)),
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _levelSegment(
          'Lvl 1',
          active: _refLevel == 1,
          onTap: () => setState(() => _refLevel = _refLevel == 1 ? null : 1),
        ),
        _levelSegment(
          'Max',
          active: _refLevel == kCreatureMaxLevel,
          onTap: () => setState(
            () => _refLevel = _refLevel == kCreatureMaxLevel
                ? null
                : kCreatureMaxLevel,
          ),
        ),
      ],
    ),
  );

  Widget _levelSegment(
    String label, {
    required bool active,
    required VoidCallback onTap,
  }) => Pressable(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: active
            ? FoE.goldBright.withValues(alpha: 0.16)
            : Colors.transparent,
        shape: FoE.facet(radius: 11),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: active ? FoE.goldBright : _inkDim,
        ),
      ),
    ),
  );

  Widget _evolutionTab(CreatureInstance creature) {
    final species = creature.species;
    if (species == null) return const SizedBox();
    final element = species.element.color;
    final isFinal = creature.stage >= 2;
    final reqLevel = isFinal ? 0 : species.evoLevelFrom(creature.stage);
    final levelOk = creature.level >= reqLevel;
    // The level is the only requirement (user 2026-07-26). The second gate — a
    // path-earned evolution feature — is gone, and with it the "Locked" state
    // below that never said what it was locked on.
    final ready = levelOk && !_evolving && !_isPreview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The full 3-stage line: reached stages in full art, the ones to come
        // as dark silhouettes (user 2026-07-18).
        _panel(title: 'Line', child: _evoChain(species, creature)),
        const SizedBox(height: 6),
        // Final form now shows nothing here (user 2026-08-28: "Final form-
        // fully evolved löschen") — the evo chain above already says a
        // creature has reached its last stage; this line only repeated it.
        if (!isFinal)
          // Just the button — greyed out until the creature can evolve. No
          // level number or requirement list (user 2026-07-18).
          _pillBtn(
            _evolving
                ? 'Evolving…'
                : ready
                ? '✨ Evolve'
                : 'Level too low',
            element,
            filled: true,
            onTap: ready ? () => _evolve(creature) : null,
          ),
      ],
    );
  }

  // The evolution line, stage 0 → 1 → 2. A stage the creature has already
  // reached shows its real art; a stage still to come shows a DARK SILHOUETTE
  // of that stage's sprite. No box around the art, and the arrows are centred
  // to the images' height (user 2026-07-18).
  Widget _evoChain(SpeciesDef species, CreatureInstance creature) {
    const arrowW = 24.0;
    return LayoutBuilder(
      builder: (context, cons) {
        // Three nodes + two arrows share the row; each image is a nodeW square,
        // so an arrow box of that height centres the arrow to the image.
        final nodeW = (cons.maxWidth - 2 * arrowW) / 3;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var s = 0; s < 3; s++) ...[
              SizedBox(
                width: nodeW,
                child: _evoNode(
                  species.stageAt(s),
                  revealed: s <= creature.stage,
                  current: s == creature.stage,
                ),
              ),
              if (s < 2)
                SizedBox(
                  width: arrowW,
                  height: nodeW,
                  child: const Center(
                    child: Icon(Icons.chevron_right, color: _inkDim, size: 20),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _evoNode(
    SpeciesStage stage, {
    required bool revealed,
    required bool current,
  }) {
    final url = stage.imageUrl;
    Widget art;
    if (url == null) {
      art = Icon(Icons.pets, color: revealed ? _inkDim : FoE.bg, size: 40);
    } else {
      // Same disk-cached loader as [_art] — see the comment there for why a
      // bare Image.network on a brand-new URL is what produced the black
      // starter-preview art.
      final img = CreatureSprite(
        url: url,
        fit: BoxFit.contain,
        height: 40,
        fallback: Icon(
          Icons.pets,
          color: revealed ? _inkDim : FoE.bg,
          size: 40,
        ),
      );
      // Locked stage → paint every opaque pixel near-black for a silhouette.
      art = revealed
          ? img
          : ColorFiltered(
              colorFilter: const ColorFilter.mode(FoE.bg, BlendMode.srcATop),
              child: img,
            );
    }
    return Column(
      children: [
        // Just the image, no box (user 2026-07-18).
        AspectRatio(aspectRatio: 1, child: art),
        const SizedBox(height: 5),
        Text(
          revealed ? stage.name : '???',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: revealed ? _ink : _inkDim,
            fontSize: 11,
            fontWeight: current ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }

  /// Everything this creature could ever learn — every stage, not just the
  /// ones already reached (a locked row still shows, greyed, so the player
  /// knows what evolving unlocks) — PLUS Attack itself (user 2026-09-06:
  /// "Behandle Attack wie jede andere Fähigkeit"): it is still free,
  /// universal and never trained (see [learnableAbilitiesFor]'s own doc on
  /// why it is excluded from the real curriculum), but this SCREEN no
  /// longer pins it in a block of its own above the loop — it flows through
  /// the same list, the same [_sortedCurriculum] ranking and the same
  /// [_abilitySort] as everything else. Unordered; see [_sortedCurriculum]
  /// for what actually renders.
  List<AbilityDef> _fullCurriculum(SpeciesDef species) {
    final attack = kAbilityDefs['attack'];
    return [
      if (attack != null) attack,
      ...learnableAbilitiesFor(species.element, 2),
    ];
  }

  /// [_fullCurriculum], ordered for display (user 2026-09-06: "Die
  /// ausgewählten Fähigkeiten sind immer zu oberst. Zusätzlich noch
  /// Sortierfunktion hinzufügen") — an EQUIPPED ability always outranks a
  /// merely-learned one, which always outranks a trainable-but-unlearned
  /// one, which always outranks a locked one; [_abilitySort] only breaks
  /// ties WITHIN that same rank; so learned-and-equipped is what genuinely
  /// stays on top no matter which sort the player picks. Attack counts as
  /// "equipped" here for exactly that reason — it is always active, so it
  /// belongs in the same top tier, not a special one above it.
  List<AbilityDef> _sortedCurriculum(
    CreatureInstance creature,
    SpeciesDef species,
  ) {
    int rank(AbilityDef a) {
      if (a.id == 'attack' || creature.equippedAbilityIds.contains(a.id)) {
        return 0;
      }
      if (creature.stage < a.unlockStage) return 3;
      if (!creature.learnedAbilityIds.contains(a.id)) return 2;
      return 1; // learned, not equipped
    }

    int byKey(AbilityDef a, AbilityDef b) => switch (_abilitySort) {
      _AbilitySort.stage =>
        a.unlockStage != b.unlockStage
            ? a.unlockStage.compareTo(b.unlockStage)
            : a.name.compareTo(b.name),
      // Strongest first — the number a player picking "by power" wants up
      // top, not buried at the bottom of an ascending list.
      _AbilitySort.power => b.power.compareTo(a.power),
      _AbilitySort.apCost => CombatEngine.abilityApCost(
        a,
      ).compareTo(CombatEngine.abilityApCost(b)),
      _AbilitySort.name => a.name.compareTo(b.name),
    };

    return _fullCurriculum(species)..sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : byKey(a, b);
    });
  }

  /// The sort control above the curriculum — IDENTICAL to the Monsters
  /// screen's own sort glyph (user 2026-09-06: "nimm die Filterfunktion
  /// beim Monsterscreen ... Diese soll genau gleich aussehen"): a bare
  /// icon-only [PopupMenuButton], not the earlier tap-to-cycle text chip,
  /// so every sort control in the app reads as the same control. See
  /// CollectionScreen._sortGlyphBtn — this is that button, verbatim, with
  /// [_AbilitySort] in place of its own sort enum.
  Widget _abilitySortControl() {
    final engaged = _abilitySort != _AbilitySort.stage;
    return Tooltip(
      message: 'Sort: ${_abilitySort.label}',
      child: PopupMenuButton<_AbilitySort>(
        tooltip: '',
        color: FoE.panelMid,
        elevation: 10,
        position: PopupMenuPosition.under,
        padding: EdgeInsets.zero,
        shape: FoE.facet(
          radius: 12,
          side: const BorderSide(color: FoE.borderGold),
        ),
        onSelected: (mode) => setState(() => _abilitySort = mode),
        itemBuilder: (_) => [
          for (final mode in _AbilitySort.values)
            PopupMenuItem<_AbilitySort>(
              value: mode,
              height: 40,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      mode.label,
                      style: FoE.label(size: 12).copyWith(
                        color: mode == _abilitySort ? FoE.goldBright : _ink,
                      ),
                    ),
                  ),
                  if (mode == _abilitySort)
                    Text(
                      '✓',
                      style: FoE.value(
                        size: 13,
                      ).copyWith(color: FoE.goldBright),
                    ),
                ],
              ),
            ),
        ],
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          alignment: Alignment.center,
          decoration: FoE.btn(active: engaged),
          child: Icon(
            Icons.swap_vert,
            size: 17,
            color: engaged ? Colors.white : FoE.goldBright,
          ),
        ),
      ),
    );
  }

  Widget _abilitiesTab(CreatureInstance creature) {
    final species = creature.species;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (species != null) ...[
          Align(alignment: Alignment.centerRight, child: _abilitySortControl()),
          const SizedBox(height: 8),
          // Attack included (user 2026-09-06: "Behandle Attack wie jede
          // andere Fähigkeit") — see [_fullCurriculum]/[_sortedCurriculum]
          // for why it's folded into this one list instead of pinned above
          // it, and [_learnedAbilityRow] for the one thing about it that
          // still has to stay special (it can't be locked, trained or
          // un-equipped).
          for (final a in _sortedCurriculum(creature, species))
            _panel(child: _learnedAbilityRow(creature, a)),
        ] else if (kAbilityDefs['attack'] case final attack?)
          _panel(child: _learnedAbilityRow(creature, attack)),
      ],
    );
  }

  /// One row in the curriculum: locked (stage not reached), learnable but
  /// not yet known (train at the Combat School — no action here, this
  /// screen is read-only about what's trainable), or learned (equip toggle,
  /// capped at [kMaxEquippedAbilities]).
  ///
  /// Attack (user 2026-09-03: free, universal, never trained — see
  /// [learnableAbilitiesFor]'s own doc) is the one id that can never be
  /// locked, trained or un-equipped, so it still needs its own trailing
  /// state — but it renders through this exact same row/panel as everything
  /// else now (user 2026-09-06: "Behandle Attack wie jede andere
  /// Fähigkeit"), not a separate block above the loop.
  Widget _learnedAbilityRow(CreatureInstance creature, AbilityDef ability) {
    if (ability.id == 'attack') {
      return _abilityRow(
        ability: ability,
        // NOT "Always equipped" — Attack sits outside the equip system
        // entirely and never occupies one of the [kMaxEquippedAbilities]
        // slots the toggle below spends.
        trailing: const Text(
          'Always available',
          style: TextStyle(
            color: FoE.positive,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    final locked = creature.stage < ability.unlockStage;
    final learned = creature.learnedAbilityIds.contains(ability.id);
    final equipped = creature.equippedAbilityIds.contains(ability.id);
    final atCap = creature.equippedAbilityIds.length >= kMaxEquippedAbilities;

    Widget trailing;
    if (locked) {
      trailing = Text(
        'Stage ${ability.unlockStage + 1}',
        style: const TextStyle(
          color: _inkDim,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      );
    } else if (!learned) {
      trailing = const Text(
        'Train at the\nCombat School',
        textAlign: TextAlign.right,
        style: TextStyle(color: _inkDim, fontSize: 11, height: 1.2),
      );
    } else {
      final canToggle = !_isPreview && (equipped || !atCap);
      trailing = Pressable(
        behavior: HitTestBehavior.opaque,
        onTap: canToggle
            ? () => _toggleEquipped(creature, ability.id, !equipped)
            : null,
        child: Opacity(
          opacity: canToggle ? 1 : 0.4,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                equipped ? Icons.check_box : Icons.check_box_outline_blank,
                size: 20,
                color: equipped ? FoE.positive : _inkDim,
              ),
              const SizedBox(width: 4),
              Text(
                equipped ? 'Equipped' : 'Equip',
                style: TextStyle(
                  color: equipped ? FoE.positive : _inkDim,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return _abilityRow(
      ability: ability,
      trailing: trailing,
      dim: locked || !learned,
    );
  }

  Future<void> _toggleEquipped(
    CreatureInstance creature,
    String abilityId,
    bool on,
  ) async {
    final next = List<String>.from(creature.equippedAbilityIds);
    if (on) {
      if (!next.contains(abilityId)) next.add(abilityId);
    } else {
      next.remove(abilityId);
    }
    await _ctrl.setEquipped(creature, next);
    if (mounted) setState(() {});
  }

  Widget _abilityRow({
    required AbilityDef ability,
    required Widget trailing,
    bool dim = false,
  }) {
    // Whether there is anything worth tapping to reveal — a plain hit with
    // no effect and no extra-hit chance has nothing more to say.
    final expandable = ability.effects.isNotEmpty || ability.extraHitChance > 0;
    final expanded = expandable && _expandedAbilityIds.contains(ability.id);
    return Opacity(
      opacity: dim ? 0.6 : 1,
      child: Pressable(
        behavior: HitTestBehavior.opaque,
        onTap: expandable
            ? () => setState(() {
                if (expanded) {
                  _expandedAbilityIds.remove(ability.id);
                } else {
                  _expandedAbilityIds.add(ability.id);
                }
              })
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  ability.element.emoji,
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ability.name,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${ability.kind.label} · Power ${ability.power} · '
                        '${CombatEngine.abilityApCost(ability)} AP',
                        style: const TextStyle(color: _inkDim, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                if (expandable)
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: _inkDim,
                  ),
                const SizedBox(width: 4),
                trailing,
              ],
            ),
            if (expanded) ...[
              const SizedBox(height: 6),
              if (ability.extraHitChance > 0)
                _abilityEffectLine(
                  Icons.blur_on,
                  ability.extraHitSameTarget
                      ? 'May hit the SAME target again: 2nd hit '
                            '${(ability.extraHitChance * 100).round()} % '
                            'chance, 3rd '
                            '${(ability.extraHitChance * ability.extraHitChance * 100).round()} %.'
                      : 'May also hit ANOTHER enemy: 2nd hit '
                            '${(ability.extraHitChance * 100).round()} % '
                            'chance, 3rd '
                            '${(ability.extraHitChance * ability.extraHitChance * 100).round()} % '
                            '— does nothing extra alone.',
                ),
              for (final e in ability.effects)
                _abilityEffectLine(
                  Icons.info_outline,
                  describeAbilityEffect(e).join('\n'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _abilityEffectLine(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(top: 4, left: 28),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: _inkDim),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: _inkDim, fontSize: 11),
          ),
        ),
      ],
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
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                color: _ink,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        RecessBar(value: frac, color: color, height: 12),
      ],
    ),
  );

  Widget _pillBtn(
    String label,
    Color color, {
    required bool filled,
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
            shape: FoE.facet(
              radius: 15,
              side: BorderSide(color: color, width: 1.6),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: filled ? Colors.white : color,
              fontSize: 13,
              fontWeight: FontWeight.w700,
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
              shape: FoE.facet(radius: 12),
            ),
            child: Text(
              '🪙 $cost',
              style: TextStyle(
                color: canPay ? Colors.white : _inkDim,
                fontSize: 12,
                fontWeight: FontWeight.w700,
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
        decoration: ShapeDecoration(
          color: element,
          shape: FoE.facet(radius: 12),
        ),
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
            fontWeight: FontWeight.w600,
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
  Widget _workPanel(CreatureInstance creature) {
    final id = creature.assignedBuildingId;
    final buildings = SettlementController().buildings;
    final idx = id == null ? -1 : buildings.indexWhere((b) => b.id == id);
    if (idx < 0) {
      return _panel(
        title: 'Work',
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
    return _panel(
      title: 'Work',
      // Back to the LEFT, title included (user 2026-08-29: "tausche es
      // wieder: ... text links" — undoes that same day's right-align).
      child: SizedBox(
        width: double.infinity,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              // Room on the RIGHT again for the icon, which moved back
              // there too (user 2026-08-29: "tausche es wieder: ... Icon
              // rechts").
              padding: const EdgeInsets.only(right: 130),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // White, not the dim ink (user 2026-08-29: "Name des
                  // Gebäudes in weiss, damit es besser auffällt") — the
                  // only line in the box worth making stand out; the rate
                  // and ETA under it stay dim.
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
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
            // [ShadowedBuildingIcon] — the exact widget the build-menu
            // cards and the map's building-detail dialog use: natural
            // aspect, standing on its own cast shadow. Bottom-anchored ONLY
            // (no `top`) is what makes it rise up past its own slot on its
            // own — the slot behind it (the text column) is far shorter
            // than the icon's own rendered height, so the art's top simply
            // ends up above the card without a guessed offset for it.
            Positioned(
              right: -16,
              bottom: -6,
              // The extra Transform.scale tried here (user 2026-08-29) was
              // taken back out the same day ("Icon zoom wieder
              // hinausnehmen bei work") — plain width again.
              child: ShadowedBuildingIcon(
                imageUrl: null,
                defId: building.buildingTypeId,
                width: 185,
              ),
            ),
          ],
        ),
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

/// Clips a child to the top [height] pixels of its box — used to keep the
/// monster's drop shadow on the coloured backdrop and off the dark sheet below.
class _TopRectClipper extends CustomClipper<Rect> {
  final double height;
  const _TopRectClipper(this.height);
  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width, height);
  @override
  bool shouldReclip(_TopRectClipper old) => old.height != height;
}
