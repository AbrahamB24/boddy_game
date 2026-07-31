import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/foe_theme.dart';
import '../settlement/widgets/meander_strip.dart';
import '../settlement/widgets/scroll_paper.dart'
    show kParchmentInk, kParchmentLight, kParchmentMid;
import '../common/widgets/app_back_button.dart';
import '../../core/ui/snack.dart';
import '../settlement/data/item_definitions.dart';
import '../settlement/services/crafting.dart';
import '../settlement/settlement_controller.dart';
import 'models/ability_def.dart';
import 'models/creature_enums.dart';
import 'models/creature_instance.dart';
import 'models/species_def.dart';
import 'services/combat_engine.dart';
import 'widgets/creature_backdrop.dart';
import 'widgets/gene_bar_toggle.dart';
import 'widgets/xp_arc.dart';
import 'services/creature_power.dart';
import 'services/creatures_controller.dart';
import '../common/widgets/recess_bar.dart';

// One creature, Pokédex-style (user 2026-07-17): the element backdrop up top
// with the monster art straddling into a white sheet below, a short description
// under the name, and element-coloured tabs for General / Stats / Evolution /
// Abilities. Resolves the creature against the controller on every build so
// rename/evolve/release updates always reflect.
class CreatureDetailScreen extends StatefulWidget {
  final String creatureId;
  const CreatureDetailScreen({super.key, required this.creatureId});

  @override
  State<CreatureDetailScreen> createState() => _CreatureDetailScreenState();
}

class _CreatureDetailScreenState extends State<CreatureDetailScreen> {
  final _ctrl = CreaturesController();
  final _settlement = SettlementController();
  bool _evolving = false;
  // Which detail tab is shown: 0 General · 1 Stats · 2 Evolution · 3 Abilities.
  int _tab = 0;

  /// Which gene the Stats tab's bars are drawn from — see [GeneBarToggle].
  bool _barsShowGrowth = false;

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


  CreatureInstance? get _creature {
    for (final c in _ctrl.creatures) {
      if (c.id == widget.creatureId) return c;
    }
    return null;
  }

  Future<void> _evolve(CreatureInstance creature) async {
    setState(() => _evolving = true);
    final error = await _ctrl.evolve(creature);
    if (!mounted) return;
    setState(() => _evolving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error ?? '✨ ${creature.displayName} evolved!',
          style: FoE.label(size: 13).copyWith(
            color: error == null ? FoE.goldBright : Colors.redAccent,
          ),
        ),
        backgroundColor: FoE.panelDark,
      ),
    );
  }

  // Rename dialog, styled to match this screen (dark sheet, Outfit font, the
  // creature's element as the accent) rather than the global FoE gold theme
  // (user 2026-07-18).
  Future<void> _rename(CreatureInstance creature) async {
    final element = creature.species?.element.color ?? FoE.gold;
    final controller = TextEditingController(text: creature.nickname ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _paper(element, 0.16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text('Rename',
            style: GoogleFonts.outfit(
                color: _ink, fontSize: 18, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: controller,
          autofocus: true,
          cursorColor: element,
          style: GoogleFonts.outfit(color: _ink, fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Empty = species name',
            hintStyle: GoogleFonts.outfit(color: _inkDim, fontSize: 13),
            enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: _track)),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: element, width: 2)),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.outfit(
                    color: _inkDim, fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text('Save',
                style: GoogleFonts.outfit(
                    color: element, fontSize: 14, fontWeight: FontWeight.w800)),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
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
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error, style: FoE.label(size: 13)),
            backgroundColor: FoE.panelDark,
          ),
        );
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
  @override
  Widget build(BuildContext context) {
    // The scaffold under the sheet takes the same tint — an overscroll bounce
    // that revealed beige would say the page was two pages.
    final scaffoldElement =
        _creature?.species?.element.color ?? FoE.gold;
    return Scaffold(
      backgroundColor: _paper(scaffoldElement, 0.10),
      body: ListenableBuilder(
        listenable: Listenable.merge([_ctrl, _settlement]),
        builder: (context, _) {
          final creature = _creature;
          if (creature == null) {
            return Center(child: Text('Creature not found', style: FoE.label()));
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
                final imgH = h * 0.35; // spans imgTop..imgTop+imgH, over the seam
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
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(30)),
                        ),
                        padding: EdgeInsets.only(top: contentTop),
                        // The bordure, on the sheet only — it is the page's
                        // printed border, and the page here starts where the
                        // element backdrop ends.
                        child: Stack(
                          children: [
                            Positioned(
                              left: 4,
                              top: 0,
                              bottom: 0,
                              width: 14,
                              child: MeanderStrip(color: _ornament),
                            ),
                            Positioned(
                              right: 4,
                              top: 0,
                              bottom: 0,
                              width: 14,
                              child: MeanderStrip(color: _ornament, flip: true),
                            ),
                            _sheet(creature, species, element),
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
                                  const Text('⚡', style: TextStyle(fontSize: 28)),
                                  const SizedBox(width: 4),
                                  Text('${totalPower(creature)}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 30,
                                        fontWeight: FontWeight.w900,
                                      )),
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

  Widget _art(CreatureInstance creature, {required double backdropBottom}) {
    final url = creature.imageUrl;
    if (url == null) {
      return const Icon(Icons.pets, color: Colors.white70, size: 90);
    }
    // The drop shadow uses the element's own shadow tone — the same colour its
    // type icon is embossed with (user request).
    final shadowColor =
        (creature.species?.element ?? CreatureElement.fire).shadowColor;
    Widget image({FilterQuality quality = FilterQuality.none}) => Image.network(
          url,
          filterQuality: quality,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) =>
              const Icon(Icons.pets, color: Colors.white70, size: 90),
        );
    return Stack(
      fit: StackFit.expand,
      children: [
        // Drop shadow behind the monster: the sprite's SHARP silhouette in the
        // element's shadow tone, a bit SMALLER than the sprite and clipped to
        // the coloured backdrop — so there is NO shadow on the dark sheet below
        // (user request).
        Positioned.fill(
          child: ClipRect(
            clipper: _TopRectClipper(backdropBottom),
            child: Transform.translate(
              offset: const Offset(2, 8),
              child: Transform.scale(
                scale: 0.9,
                alignment: Alignment.bottomCenter,
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                      shadowColor, BlendMode.srcATop),
                  child: image(),
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(child: image()),
      ],
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
      // bands sit at 4 and run 14 wide, so they end at exactly 18 — which is
      // where the content used to start, i.e. touching them. 28 leaves ten
      // pixels of paper on either side; [ParchmentPage] does the same thing
      // with its own 24 against the same bands.
      padding: const EdgeInsets.symmetric(horizontal: 28),
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
                    child: Text('Level ${creature.level}',
                        style: TextStyle(
                            color: element,
                            fontSize: 17,
                            fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            atMax ? 'MAX' : '${creature.xp} / $need EP',
            style: const TextStyle(
                color: _inkDim, fontSize: 12, fontWeight: FontWeight.w600),
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
              // Small edit (rename) button, right of the name/gender.
              GestureDetector(
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
              style: const TextStyle(color: _inkDim, fontSize: 12, height: 1.35),
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _tab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: on
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.lerp(element, Colors.white, 0.22)!,
                    element,
                  ],
                )
              : null,
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
  Widget _panel({String? title, required Widget child}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: _recess(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: title == null
          ? child
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _panelTitle(title),
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
    decoration: ShapeDecoration(color: kParchmentInk.withValues(alpha: 0.07), shape: FoE.facet(radius: radius, side: BorderSide(color: kParchmentInk.withValues(alpha: 0.14)))),
    child: child,
  );

  /// A panel's heading — small, spaced capitals, cut into the card.
  static Widget _panelTitle(String label, {Widget? trailing}) => Row(
    children: [
      Expanded(
        child: Text(
          label.toUpperCase(),
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
    final atMax = creature.level >= kCreatureMaxLevel;
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
    // CONDITION first, then what it is GOOD AT, then what you can do about
    // either. Each is a card of its own, so the three questions stop running
    // together down one column.
    final care = creature.isHealing
        ? _healingInline(creature, element)
        : creature.hp < creature.maxHp
        ? _potionInline(creature, element)
        : !atMax
        ? Text(_passiveXpText(creature),
            style: const TextStyle(color: _inkDim, fontSize: 11))
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panel(
          title: 'Condition',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The bar's own bottom padding is what separated it from the next
              // block; inside a card the card's padding does that job.
              Padding(
                padding: const EdgeInsets.only(bottom: 0),
                child: _barRow(
                  'HP',
                  '${creature.hp} / ${creature.maxHp}',
                  hpFrac,
                  hpColor,
                  bottomPad: care == null ? 0 : 12,
                ),
              ),
              if (care != null) care,
            ],
          ),
        ),
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
        const SizedBox(height: 8),
        _pillBtn('Release', Colors.redAccent, filled: false,
            onTap: () => _release(creature)),
        if (_settlement.isDev) ...[
          const SizedBox(height: 8),
          _pillBtn('🛠 +500 XP (Dev)', _inkDim,
              filled: false, onTap: () => _ctrl.devGainXp(creature, 500)),
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
    decoration: ShapeDecoration(color: element.withValues(alpha: 0.14), shape: FoE.facet(radius: 11, side: BorderSide(color: element.withValues(alpha: 0.5)))),
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
    final values = {
      for (final s in CreatureStat.values) s: creature.statValue(s),
    };
    // WHICH GENE THE BARS DRAW (user 2026-07-27) — the level-up caption is a
    // switch now, the same one the breeding and Hatchery tables carry. The
    // scale follows it: a growth of +1.6 against a stat of 80 would otherwise
    // be a hairline on every row.
    final barValues = _barsShowGrowth
        ? {
            for (final s in CreatureStat.values)
              s: (creature.statSlope[s] ?? 0),
          }
        : {for (final s in CreatureStat.values) s: values[s]!.toDouble()};
    final maxVal = barValues.values.reduce((a, b) => a > b ? a : b);
    int totalOf(List<CreatureStat> group) =>
        group.fold(0, (sum, s) => sum + values[s]!);

    // The group's summed value rides in its card's heading, over the value
    // column, so it lines up with the rows beneath it.
    Widget header(String label, int total) => _panelTitle(
      label,
      trailing: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text('$total',
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: _ink, fontSize: 14, fontWeight: FontWeight.w800)),
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
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            SizedBox(
              width: 86,
              child: Text(stat.label,
                  style: const TextStyle(color: _ink, fontSize: 12)),
            ),
            Expanded(
              child: RecessBar(
                value: maxVal > 0 ? barValues[stat]! / maxVal : 0,
                color: color,
                height: 10,
              ),
            ),
            SizedBox(
              width: 32,
              child: Text('${values[stat]}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      color: _ink, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
            // Growth per level (the sampled slope gene).
            SizedBox(
              width: 42,
              child: Text('+${growth.toStringAsFixed(1)}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      color: _inkDim,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600)),
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
        // The switch sits ABOVE the groups, once. Inside the first card it
        // would look like a setting for Combat only.
        Align(
          alignment: Alignment.centerRight,
          child: GeneBarToggle(
            showGrowth: _barsShowGrowth,
            onChanged: (v) => setState(() => _barsShowGrowth = v),
            ink: _ink,
            inkFaint: _inkDim,
            accent: FoE.goldBright,
          ),
        ),
        const SizedBox(height: 8),
        group('Combat', kCombatStats),
        group('Work', kCivilianStats),
        group('Expedition', _expeditionStats),
      ],
    );
  }

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
    final ready = levelOk && !_evolving;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The full 3-stage line: reached stages in full art, the ones to come
        // as dark silhouettes (user 2026-07-18).
        _panel(title: 'Line', child: _evoChain(species, creature)),
        const SizedBox(height: 6),
        if (isFinal)
          const Center(
            child: Text('✨ Final form — fully evolved.',
                style: TextStyle(color: _inkDim, fontSize: 13)),
          )
        else
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

  Widget _evoNode(SpeciesStage stage,
      {required bool revealed, required bool current}) {
    final url = stage.imageUrl;
    Widget art;
    if (url == null) {
      art = Icon(Icons.pets, color: revealed ? _inkDim : FoE.bg,
          size: 40);
    } else {
      final img = Image.network(
        url,
        filterQuality: FilterQuality.none,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => Icon(Icons.pets,
            color: revealed ? _inkDim : FoE.bg, size: 40),
      );
      // Locked stage → paint every opaque pixel near-black for a silhouette.
      art = revealed
          ? img
          : ColorFiltered(
              colorFilter: const ColorFilter.mode(
                  FoE.bg, BlendMode.srcATop),
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

  Widget _abilitiesTab(CreatureInstance creature) {
    final species = creature.species;
    final abilities = List.of(species?.abilities ?? const [])
      ..sort((a, b) => a.unlockStage.compareTo(b.unlockStage));
    if (abilities.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text('No abilities defined.',
              style: TextStyle(color: _inkDim, fontSize: 13)),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final sa in abilities)
          _panel(
            child: _abilityRow(creature, sa.abilityId, sa.unlockStage),
          ),
      ],
    );
  }

  Widget _abilityRow(
      CreatureInstance creature, String abilityId, int unlockStage) {
    final ability = kAbilityDefs[abilityId];
    final unlocked = creature.stage >= unlockStage;
    return Padding(
      // The card supplies the gap between abilities now.
      padding: EdgeInsets.zero,
      child: Opacity(
        opacity: unlocked ? 1 : 0.5,
        child: Row(
          children: [
            Text(ability?.element.emoji ?? '⚔️',
                style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ability?.name ?? abilityId,
                      style: const TextStyle(
                          color: _ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  Text(
                    ability == null
                        ? 'Unknown ability'
                        : '${ability.kind.label} · Power ${ability.power} · ${CombatEngine.abilityApCost(ability)} AP',
                    style: const TextStyle(color: _inkDim, fontSize: 11),
                  ),
                ],
              ),
            ),
            Text(unlocked ? '✓' : 'Stage ${unlockStage + 1}',
                style: TextStyle(
                    color: unlocked ? FoE.positive : _inkDim,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  // ── Shared white-theme widgets ────────────────────────────
  Widget _barRow(String label, String value, double frac, Color color,
          {double bottomPad = 12}) =>
      Padding(
    padding: EdgeInsets.only(bottom: bottomPad),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: const TextStyle(
                    color: _inkDim, fontSize: 12, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(value,
                style: const TextStyle(
                    color: _ink, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 5),
        RecessBar(value: frac, color: color, height: 12),
      ],
    ),
  );

  Widget _pillBtn(String label, Color color,
          {required bool filled, VoidCallback? onTap}) =>
      SizedBox(
    width: double.infinity,
    child: GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          alignment: Alignment.center,
          decoration: ShapeDecoration(color: filled ? color : Colors.transparent, shape: FoE.facet(radius: 15, side: BorderSide(color: color, width: 1.6))),
          child: Text(label,
              style: TextStyle(
                  color: filled ? Colors.white : color,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
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
          child: Text('In treatment · ${_fmt(left)} left',
              style: const TextStyle(color: _inkDim, fontSize: 12)),
        ),
        GestureDetector(
          onTap: canPay
              ? () async {
                  final err = await _ctrl.skipHealWithGold(creature);
                  if (!mounted || err == null) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(err, style: FoE.label(size: 12))),
                  );
                }
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: ShapeDecoration(color: canPay ? element : _track, shape: FoE.facet(radius: 12)),
            child: Text('🪙 $cost',
                style: TextStyle(
                    color: canPay ? Colors.white : _inkDim,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(ko ? 'Revive · K.O.' : 'Use an item · missing $missing HP',
            style: const TextStyle(color: _inkDim, fontSize: 12)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (def, count) in held)
              GestureDetector(
                onTap: () => _usePotion(def, creature),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: ShapeDecoration(color: element, shape: FoE.facet(radius: 12)),
                  child: Text(
                    def.kind == ItemKind.revive
                        ? '${def.emoji} ${def.name} ×$count · → ${(creature.maxHp * def.magnitude).round()} HP'
                        : '${def.emoji} ${def.name} ×$count · +${healFromItem(def, missing.toDouble()).round()} HP',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  String _passiveXpText(CreatureInstance creature) {
    if (!creature.isAssigned) {
      return '💤 Idle — station it in the Training Grounds to level it over '
          'time, or fight: a won battle is the fastest XP there is.';
    }
    final training = CreaturesController().isInTrainingRole(creature);
    final rate = CreaturesController().xpRatePerHour(creature);
    // Every building with a work post pays the same work rate since 2026-07-30,
    // so a zero here means the rate itself is dialled to nothing — say so
    // instead of dividing by zero into "∞ to Lv N".
    if (rate <= 0) {
      return '🔨 Working — no XP here. The work rate is set to zero; the '
          'Training Grounds and fighting still level a monster.';
    }
    final hours = (xpToNextLevel(creature.level) - creature.xp) / rate;
    return '${training ? '🏋️ Training' : '🔨 Working'}: '
        '+${rate.toStringAsFixed(0)} XP/h · ~${_fmtDays(hours)} to Lv ${creature.level + 1}.';
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
