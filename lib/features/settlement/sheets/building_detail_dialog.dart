import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/foe_theme.dart';
import '../../../core/ui/duration_format.dart';
import '../../../core/ui/number_format.dart';
import '../../../core/ui/snack.dart';
import '../../common/widgets/recess_bar.dart';
import '../../creatures/battle_screen.dart';
import '../../creatures/breeding_screen.dart';
import '../../creatures/expeditions_screen.dart';
import '../../creatures/hatchery_screen.dart';
import '../../creatures/healing_hut_screen.dart';
import '../../creatures/models/area.dart' show kResourceEmoji;
import '../../creatures/models/combatant.dart';
import '../../creatures/models/creature_enums.dart'
    show
        CreatureRarity,
        creatureLevelCap,
        kBuilderCampBuildingId,
        kScoutPostBuildingId,
        kWorkshopBuildingId,
        kDungeonPortalBuildingId,
        kBreedingHutBuildingId,
        kHatcheryBuildingId,
        kHealingHutBuildingId,
        kTradingPostBuildingId,
        kTrainingGroundsBuildingId,
        kTrainingXpPerHour,
        workXpPerHourAt;
import '../../creatures/models/creature_instance.dart';
import '../../creatures/models/species_def.dart';
import '../../creatures/overworld_screen.dart';
import '../../creatures/services/creatures_controller.dart';
import '../../creatures/widgets/creature_sprite.dart';
import '../../onboarding/intro_flow.dart';
import '../crafting_screen.dart';
import '../data/building_definitions.dart';
import '../data/era_definitions.dart' show EraDef;
import '../data/goods_definitions.dart';
import '../data/resource_icons.dart';
import '../data/workshop_role_effects.dart';
import '../management_screen.dart';
import '../market_screen.dart';
import '../models/placed_building.dart';
import '../settlement_controller.dart';
import '../widgets/assign_workers_sheet.dart';
import '../widgets/building_icon.dart';
import '../widgets/meander_strip.dart';
import '../widgets/parchment_sheet.dart';
import '../widgets/scroll_paper.dart'
    show
        kActionGreen,
        kParchmentLight,
        kParchmentMid,
        kParchmentDeep,
        kParchmentInk,
        parchmentButton,
        parchmentButtonInk;
import 'building_upgrade_sheet.dart';

/// The warm accent for labels on the building dialog's parchment (user
/// 2026-07-23): a burnt amber that reads on the cream where the app's light
/// golds would vanish. File-level so the dialog and the standalone
/// _BuildCountdown widget share the one value.
const Color _kDlgAccent = FoE.gold;

// Training battle vs. 1-3 random wild creatures near the team's level.
// Lives at the Training Grounds (user decision 2026-07-17, moved off the
// Monsters screen): the place you train is the place you spar.
Future<void> _startTrainingBattle(BuildContext context) async {
  final creatures = CreaturesController();
  final team = creatures.battleTeam();
  // No pop-up any more (user 2026-08-29: "wirklich alle pop up
  // nachrichten... löschen") — tapping Training with nobody battle-ready
  // just does nothing.
  if (team.isEmpty) return;
  final species = kSpeciesDefs.values.toList();
  if (species.isEmpty) return;
  final rng = math.Random();
  final avgLevel = (team.fold(0, (s, c) => s + c.level) / team.length).round();
  final enemies = List.generate(
    1 + rng.nextInt(math.min(3, species.length)),
    (i) => Combatant.fromSpecies(
      species[rng.nextInt(species.length)],
      level: math.max(1, avgLevel - 1 + rng.nextInt(3)),
      id: 'e_$i',
      rng: rng,
    ),
  );
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) =>
          BattleScreen(team: team, enemies: enemies, title: 'Training Battle'),
    ),
  );
}

// ── Detail dialog (normal mode) ───────────────────────────
/// The building detail dialog: art, name, level, effects, upgrade, era-ascend
/// and the primary "what this building is for" actions. Opened by tapping a
/// building on the settlement map, and (since 2026-08-31) from a building's
/// row in the Management screen's Housing tab — the same dialog either way,
/// just given an explicit [SettlementController] instead of reading it off
/// `widget.ctrl` the way the map's own State used to.
Future<void> showBuildingDetailDialog(
  BuildContext context,
  SettlementController ctrl,
  PlacedBuilding b, {
  VoidCallback? onOpenBuildMenu,
}) {
  final def = kBuildingDefs[b.buildingTypeId]!;
  return showDialog<void>(
    context: context,
    builder: (_) => AnimatedBuilder(
      animation: ctrl,
      builder: (context, _) {
        // Re-derive the live building each rebuild — the `b` captured above
        // is a snapshot and goes stale the moment laborers are (re)assigned.
        final liveB = ctrl.buildings.firstWhere(
          (x) => x.id == b.id,
          orElse: () => b,
        );
        final connected = ctrl.connectedBuildingIds.contains(liveB.id);
        final functional = liveB.isComplete && connected;
        return Dialog(
          backgroundColor: Colors.transparent,
          // The app's default DialogTheme (parchment_theme.dart) draws a
          // faint light border around every Material Dialog's own laid-out
          // bounds. Harmless when a dialog's content stays inside those
          // bounds — invisible, exactly covered by the content's own
          // matching edge — but THIS dialog deliberately lets the art rise
          // past them (Clip.none below), so that inherited border stayed
          // put at the "official" top edge and showed through every gap in
          // the roofline above it (user 2026-08-27: "die Kante der Box
          // schimmert durch das Gebäude hindurch"). The visible card is the
          // inner Container's own gradient, which needs no second, redundant
          // border drawn behind it.
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 24,
          ),
          child: Stack(
            // Clip.none twice over (here and in the scroll view): the art is
            // bottom-anchored in its slot and must be free to rise past the
            // dialog's top edge, the way the build-menu cards do.
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 400,
                // The build menu's PARCHMENT is the dialog surface too (user
                // 2026-07-23) — one warm visual language for both places you
                // look at a building.
                //
                // NOT clipped at the Container level — the art further down
                // ([_artPanel]) deliberately rises past THIS box's own top
                // edge (see the Clip.none comments above), so clipping here
                // would cut the art off along with the band. The bands get
                // their own ClipRRect instead (below), sized to this WHOLE
                // Container rather than to each band's own narrow box — a
                // radius equal to the band's own width clipped away nearly
                // the entire band near the top instead of just the sliver
                // that actually overlaps the card's true corner curve (user
                // 2026-08-31, after the first attempt: "soll auch hier ganz
                // bis zum Rand der Box kommen").
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
                    // Ornament FIRST — it is wallpaper, so it belongs behind
                    // the content and never over a line of text (user
                    // 2026-07-22).
                    //
                    // The meander band is BACK (user 2026-08-31: "hier das
                    // Mäanderband auch hinzufügen") — this dialog was the one
                    // exception that dropped it for a carved groove instead
                    // (2026-08-27: "lösche die Dreieckverzierung und ersetze
                    // sie mit etwas, was mehr passt"), back when the band was
                    // still a rough zigzag guess; now that it is traced
                    // pixel-for-pixel off the real key pattern, every sheet
                    // wears the same one again.
                    // No Center wrapper (unlike the groove it replaces) — a
                    // bare CustomPaint (which MeanderStrip is) has no
                    // intrinsic size, so Center's loose constraints collapsed
                    // it to Size.zero and the band never painted (user
                    // 2026-08-31: "ist noch nicht da"). Positioned's own
                    // tight box, straight onto the widget, is what
                    // ParchmentPage's own bands already rely on.
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          children: [
                            // Flush to the box's own top/bottom edge (user
                            // 2026-09-01: "hier auch") — the same fillHeight
                            // fix the era panel and the away-digest sheet
                            // got: a hard-edged card, not a free page
                            // margin, so the usual centred-with-margin run
                            // left a visible gap at both ends.
                            Positioned(
                              left: 14,
                              top: 0,
                              bottom: 0,
                              width: 16,
                              child: MeanderStrip(
                                color: _dlgOrnament,
                                fillHeight: true,
                              ),
                            ),
                            Positioned(
                              right: 14,
                              top: 0,
                              bottom: 0,
                              width: 16,
                              child: MeanderStrip(
                                color: _dlgOrnament,
                                flip: true,
                                fillHeight: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: SingleChildScrollView(
                            clipBehavior: Clip.none,
                            // Wide side padding: the meander bands live in that
                            // margin, so the text must keep clear of it.
                            padding: const EdgeInsets.fromLTRB(36, 14, 36, 14),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // ── Hero: art (rising out of the card), name, level
                                //    pill, what it does ───────────────────────────
                                // Footprint + level + XP/state now live in the hero masthead
                                // (user 2026-07-24) — the separate stat-chip box is gone.
                                // Guided tutorial: one banner explaining
                                // this whole dialog's parts, right where
                                // the player lands after tapping the
                                // spotlit Healing Hut (user 2026-08-24:
                                // "Detailscreen erklären: Xp, Effekte,
                                // Upgrade, Monster einsetzen").
                                if (ctrl.introStep == IntroStep.assignHealer &&
                                    liveB.buildingTypeId ==
                                        kHealingHutBuildingId) ...[
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: FoE.gold.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: FoE.borderGold),
                                    ),
                                    child: Text(
                                      'The level bar up top tracks its XP. '
                                      '"Effects" is what it produces right '
                                      'now; "Upgrade" makes it produce '
                                      'more. Below that, post a monster to '
                                      'its medicine role — a hut with '
                                      'nobody stationed heals no one.',
                                      style: FoE.label(
                                        size: 11,
                                      ).copyWith(color: _dlgInk),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                _heroRow(ctrl, liveB, def, functional),
                                const SizedBox(height: 10),
                                // Under construction: the countdown replaces the
                                // production card entirely — nothing is produced yet.
                                if (!liveB.isComplete)
                                  _sectionCard(
                                    title: 'Under construction',
                                    child: _BuildCountdown(
                                      ctrl: ctrl,
                                      buildingId: liveB.id,
                                    ),
                                  )
                                else
                                  // ── Effects: base output, housing, who works here, total ──
                                  // (user 2026-07-24: a house's gold + housing are EFFECTS, so
                                  // the card is "Effects", not just "Production".)
                                  _sectionCard(
                                    title: 'Effects',
                                    // PAUSE, as a small trailing button (user
                                    // 2026-08-27) — moved off the bottom
                                    // pill row and onto this title, the
                                    // same "green circle" the Upgrade card
                                    // wears. Only for buildings that
                                    // actually RUN something: pausing a
                                    // house or a store would be a switch
                                    // with nothing behind it, since housing
                                    // and storage are what a building IS,
                                    // not what it does, and keep counting
                                    // either way.
                                    trailing: _canPause(def)
                                        ? GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () => ctrl.setPaused(
                                              liveB.id,
                                              !liveB.isPaused,
                                            ),
                                            child: Container(
                                              width: 24,
                                              height: 24,
                                              decoration: const BoxDecoration(
                                                color: kActionGreen,
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                liveB.isPaused
                                                    ? Icons.play_arrow
                                                    : Icons.pause,
                                                size: 15,
                                                color: Colors.white,
                                              ),
                                            ),
                                          )
                                        : null,
                                    child: _productionSection(
                                      ctrl,
                                      liveB,
                                      def,
                                      functional,
                                    ),
                                  ),
                                const SizedBox(height: 6),
                                // Crafting recipe + the notes that belong to a staffed
                                // building (the workers themselves live in the production
                                // card above).
                                if (liveB.isComplete &&
                                    def.workshops.isNotEmpty) ...[
                                  _workshopExtras(liveB, def, functional),
                                  const SizedBox(height: 4),
                                ],
                                // ── Manage: the one door into staffing
                                // every post this building has (user
                                // 2026-08-27) — between Effects and
                                // Upgrade, replacing the per-post "+". Sits
                                // CLOSER to Effects than to Upgrade (user
                                // 2026-08-31: "der Manage Button gehört zu
                                // Effects") — it staffs the posts Effects
                                // reads out, Upgrade is a separate decision.
                                if (liveB.isComplete &&
                                    functional &&
                                    def.workshops.isNotEmpty) ...[
                                  _primaryActionButton(
                                    'Manage Work',
                                    () => _manageWorkers(
                                      context,
                                      ctrl,
                                      liveB,
                                      def,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                ],
                                // ── Upgrade: what it buys, cost inside the button ──
                                if (liveB.isComplete &&
                                    ctrl.isUpgradable(def)) ...[
                                  _sectionCard(
                                    title: 'Upgrade',
                                    // Small right-aligned peek at the effects at MAX level
                                    // (user 2026-07-24) — replaces the big bottom button.
                                    //
                                    // In a GREEN CIRCLE (user 2026-07-26: "damit man sieht,
                                    // dass es ein Button ist"). A bare glyph on parchment
                                    // reads as decoration next to a heading; the settlement's
                                    // action green is what everything tappable already wears,
                                    // so the circle is the whole affordance.
                                    trailing: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => showBuildingUpgradeSheet(
                                        context,
                                        def,
                                      ),
                                      child: Container(
                                        width: 24,
                                        height: 24,
                                        decoration: const BoxDecoration(
                                          color: kActionGreen,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.query_stats,
                                          size: 15,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    child: _upgradeSection(
                                      context,
                                      ctrl,
                                      liveB,
                                      def,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                // Housing lives HERE, not in the top bar (user decision
                                // 2026-07-17): the Castle is the settlement's
                                // administrative heart, so its dialog owns the population
                                // overview. isMainBuilding, not connectivity — the hall IS
                                // the road network's root and never needs a connection.
                                // Era ascension (user 2026-07-22): unlocked by the region
                                // boss, performed and PAID here — the hall is where the
                                // settlement itself levels up.
                                if (liveB.isComplete &&
                                    def.isMainBuilding &&
                                    ctrl.ascendableEra != null) ...[
                                  const SizedBox(height: 4),
                                  _ascendButton(
                                    context,
                                    ctrl,
                                    ctrl.ascendableEra!,
                                  ),
                                  const SizedBox(height: 8),
                                ],
                                // ── What this building lets you DO ─────────────
                                _actionArea(context, liveB, def, functional),
                                // THE thing it is for, LAST (user 2026-07-27):
                                // the biggest button on the card, at the foot
                                // of it, so the dialog ends on the way in
                                // rather than on a row of numbers.
                                for (final action in _primaryActions(
                                  ctrl,
                                  context,
                                  liveB,
                                  def,
                                  functional,
                                  onOpenBuildMenu: onOpenBuildMenu,
                                )) ...[const SizedBox(height: 12), action],
                                const SizedBox(height: 2),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // No ✕ (user 2026-07-22) — the level sits where it used to
              // be; tapping outside the dialog closes it.
            ],
          ),
        );
      },
    ),
  );
}

/// The era-ascension action (user 2026-07-22): names the target era, shows
/// the full cost, refuses with the reason. Gold accent — this is the biggest
/// button the settlement has.
Widget _ascendButton(
  BuildContext context,
  SettlementController ctrl,
  EraDef nextEra,
) {
  final cost = ctrl.eraAscensionCost(nextEra.order);
  final stock = ctrl.resources?.asMap ?? const {};
  final afford = cost.entries.every((e) => (stock[e.key] ?? 0) >= e.value);
  final costLabel = cost.entries
      .map(
        (e) =>
            '${kGoodsDefs[e.key]?.emoji ?? kResourceEmoji[e.key] ?? e.key} '
            '${e.value.toInt()}',
      )
      .join('  ');
  return GestureDetector(
    onTap: () async {
      final err = await ctrl.ascendEra();
      if (!context.mounted) return;
      if (err != null) {
        context.snack(err, error: true);
      } else {
        Navigator.pop(context);
        context.snack(
          '${nextEra.displayEmoji} You reach ${nextEra.displayName}! '
          'Monsters can now reach Lv ${creatureLevelCap(nextEra.order)}.',
        );
      }
    },
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: parchmentButton(active: afford),
      child: Column(
        children: [
          Text(
            // A PLACE and a distance, never a date: you have pushed further,
            // nothing has elapsed (see era_definitions.dart).
            //
            // No icon, no dot (user 2026-08-31: "überall die Icons
            // streichen und den Punkt zwischen Zahl und Text").
            'Push on to Region ${nextEra.order}  ${nextEra.displayName}',
            style: FoE.label(size: 13).copyWith(
              color: parchmentButtonInk(active: afford),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Cost: $costLabel · monsters up to '
            'Lv ${creatureLevelCap(nextEra.order)}',
            style: FoE.dim(size: 10).copyWith(
              color: afford ? parchmentButtonInk(active: true) : FoE.danger,
            ),
          ),
        ],
      ),
    ),
  );
}

// ── Detail dialog pieces (reference layout, user 2026-07-22) ─
/// The recess a section sits in — a shade sunk into the parchment (user
/// 2026-07-23), so a grouped block reads as a pressed panel rather than a
/// second colour.
final Color _dlgInset = kParchmentDeep.withValues(alpha: 0.55);

/// One grouped block of the dialog (user 2026-07-22, modern pass): a titled
/// recess. Grouping is what turned a long run of loose rows into something
/// scannable — production, upgrade and construction each own a card.
Widget _sectionCard({
  required Widget child,
  String? title,
  Widget? trailing,
}) => Container(
  padding: EdgeInsets.fromLTRB(12, title == null ? 12 : 9, 12, 12),
  decoration: ShapeDecoration(color: _dlgInset, shape: FoE.facet(radius: 14)),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (title != null) ...[
        Row(
          children: [
            Expanded(
              child: Text(
                title.toUpperCase(),
                style: FoE.dim(size: 9).copyWith(
                  color: _dlgInkFaint,
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            // A small right-aligned action for the section (e.g. the Upgrade
            // card's "effects at full upgrade" peek, user 2026-07-24).
            if (trailing != null) trailing,
          ],
        ),
        const SizedBox(height: 8),
      ],
      child,
    ],
  ),
);

/// Art, name, what the building does, level and footprint — the card's
/// masthead. The footprint (2×2) and the XP/state sit UNDER the level (user
/// 2026-07-24), which retired the separate stat-chip box; the description
/// reads BETWEEN the art and that column (user 2026-07-26) rather than as a
/// full-width line beneath both.
Widget _heroRow(
  SettlementController ctrl,
  PlacedBuilding b,
  BuildingDef def,
  bool functional,
) {
  // XP/h a worker earns here: the training rate, else the settlement-wide
  // work rate — EVERY building that stations monsters pays it (user
  // 2026-07-30), so this pill is now on every staffed building instead of the
  // eleven that happened to carry an `xp` effect.
  final xpRate = def.workshops.isEmpty
      ? 0.0
      : def.workshops.any((w) => w.resource == WorkshopRole.kTraining)
      ? kTrainingXpPerHour
      : workXpPerHourAt(b.level);
  final (String, Color)? status = !b.isComplete
      ? ('Building', _dlgAccent)
      : !functional
      ? ('No road', FoE.danger)
      : xpRate > 0
      ? ('${xpRate.toStringAsFixed(0)} XP/h', _dlgInk)
      : null;
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _artPanel(def),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // No description caption below the name any more
                      // (user 2026-08-27: "Beschreibung des Gebäudes
                      // überall entfernen") — the Effects card right
                      // below already says what the building does, in
                      // more exact terms than this summary line ever did.
                      Text(
                        def.name,
                        style: FoE.title(size: 16).copyWith(color: _dlgInk),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Level, then footprint, then XP/state — right-aligned.
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // The hall shows its level too (user 2026-07-25): it
                    // isn't upgradable by hand, but it gains a level with
                    // every era — i.e. every region boss — so the number is
                    // real progress the player earned.
                    if (ctrl.isUpgradable(def) || def.isMainBuilding)
                      _levelPill(b.level),
                    // The FOOTPRINT, smaller and with its own icon (user
                    // 2026-07-26). At the level pill's size a bare "4×4"
                    // competed with the level for the eye; shrunk and
                    // labelled, it reads as the aside it is.
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.grid_on, size: 10, color: _dlgInkSoft),
                          const SizedBox(width: 3),
                          Text(
                            '${def.gridW}×${def.gridH}',
                            style: FoE.dim(
                              size: 9,
                            ).copyWith(color: _dlgInkSoft),
                          ),
                        ],
                      ),
                    ),
                    if (status != null)
                      Text(
                        status.$1,
                        style: FoE.value(size: 11).copyWith(color: status.$2),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );
}

/// Just the level, no box (user 2026-07-23) — plain accent text.
Widget _levelPill(int level) => Padding(
  padding: const EdgeInsets.only(top: 2),
  child: Text(
    'Lv $level',
    style: FoE.label(
      size: 12,
    ).copyWith(color: _dlgAccent, fontWeight: FontWeight.w800),
  ),
);

/// Everything this building lets you DO, in one place at the foot of the
/// card (user 2026-07-22, modern pass). The features are compact PILLS in a
/// wrap — a stack of full-width buttons made a Castle dialog scroll
/// for no reason. The two that carry live numbers (healing's price, the
/// build-skip toll) stay full width, because that number is the decision.
/// A building can be paused when it RUNS something: a work post, or a
/// worker-free `production` effect. Everything else has nothing to stop.
bool _canPause(BuildingDef def) =>
    def.workshops.isNotEmpty || def.effectKeys('production').isNotEmpty;

/// Any building still under construction can be bought out.
///
/// The Castle's own "🏠 Population X/Y" pill — a second, redundant door
/// into its own bottom sheet — is GONE (user 2026-08-31: "diesen
/// Population Button inkl. dem Menü kann gelöscht werden"). It was
/// Castle-only (`def.isMainBuilding`); every sheltering building, Castle
/// included, already has the wide "Population" button below
/// ([_primaryActions]) leading to the SAME budget on Management's Housing
/// tab, so nothing lost the door — it just stopped having two of them.
Widget _actionArea(
  BuildContext context,
  PlacedBuilding b,
  BuildingDef def,
  bool functional,
) => b.isComplete ? const SizedBox.shrink() : _skipBuildButton(context, b);

/// THE thing this building is FOR — one big green button at the head of the
/// dialog (user 2026-07-27: "der Breeding button muss viel prominenter sein,
/// da dies die hauptfunktion ist. Bitte für andere Gebäude mit ähnlichen
/// Funktionen übernehmen").
///
/// It used to be a small pill in a wrap at the very bottom, under Effects and
/// Upgrade — so the Breeding Hut's dialog opened with its worker roster and
/// buried the one control the building exists for. Every building whose whole
/// point is a screen or a sheet now leads with it, in the same green the
/// Upgrade button wears.
///
/// Returns null for a building with no such feature (a plain producer), and
/// for one that is not [functional] yet — an unfinished or unconnected
/// building cannot open anything.
/// A LIST since 2026-07-30 (user: "Worker Verwaltung über Castle und
/// Population über jedes Haus aufrufbar machen"): a building can lead to more
/// than one thing — the Castle shelters monsters AND runs the workforce
/// — and the old single-return shape could only ever offer the first of them.
List<Widget> _primaryActions(
  SettlementController ctrl,
  BuildContext context,
  PlacedBuilding b,
  BuildingDef def,
  bool functional, {
  VoidCallback? onOpenBuildMenu,
}) {
  if (!functional) return const [];
  final (String, VoidCallback)? action = switch (def.id) {
    // A SCREEN now, like every other building feature (user 2026-07-27: "ich
    // will alle verletzten Monster angezeigt bekommen und einzelne heilen
    // können"). It was a live widget right here, because "heal everybody for
    // one price" fits on a button — a list of the wounded with a price each
    // does not.
    // "Healing", not "Healing Hut" (user 2026-08-27) — every other
    // button here names the ACTION, not the building ("Breeding",
    // "Market", "Crafting"); this was the one still repeating its own
    // building name.
    kHealingHutBuildingId => (
      'Healing',
      () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const HealingHutScreen()),
      ),
    ),
    kDungeonPortalBuildingId => (
      'Overworld',
      () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const OverworldScreen()),
      ),
    ),
    kBreedingHutBuildingId => (
      'Breeding',
      () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const BreedingScreen()),
      ),
    ),
    // Incubating and hatching belong to the HATCHERY (user 2026-07-26: "ein
    // ei ausbrüten muss zu der hatchery"), so the building opens them the
    // same way the Breeding Hut opens mating.
    kHatcheryBuildingId => (
      'Hatchery',
      () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const HatcheryScreen()),
      ),
    ),
    // A SCREEN, like the Hatchery and the Breeding Hut (user 2026-07-27) —
    // the Market was the last building feature that still opened as a sheet.
    kTradingPostBuildingId => (
      'Market',
      () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MarketScreen()),
      ),
    ),
    // The place you train is the place you spar (user decision 2026-07-17:
    // moved off the Monsters screen).
    kTrainingGroundsBuildingId => (
      'Training battle',
      () => _startTrainingBattle(context),
    ),
    // The camp houses the builders, so it is a door to the Build menu (user
    // 2026-07-29: "das build menü soll auch durch das build camp aufrufbar
    // sein") — the same menu the corner pad opens, not a second one.
    kBuilderCampBuildingId when onOpenBuildMenu != null => (
      'Build',
      onOpenBuildMenu,
    ),
    // The post grants the expedition slots and shortens every trip, so it is
    // where the trips live (user 2026-07-29: "Trips soll über den Scoutpost
    // erreichbar sein").
    // The workbench is a SCREEN now (user 2026-07-29) — a recipe has a cost,
    // a duration, an effect and a stock, and none of those fit on the chip
    // the dialog used to offer it as.
    kWorkshopBuildingId => (
      'Crafting',
      () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CraftingScreen()),
      ),
    ),
    kScoutPostBuildingId => (
      'Expeditions',
      () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ExpeditionsScreen()),
      ),
    ),
    _ => null,
  };
  final actions = <(String, VoidCallback)>[if (action != null) action];
  void open(int tab) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => ManagementScreen(initialTab: tab)),
  );
  // THE TRIBAL CENTER RUNS THE WORKFORCE (user 2026-07-30). Who works where was
  // reachable only from the Manage screen's second tab — a settlement-wide
  // decision with no door in the settlement. The hall is where that door
  // belongs: it is the one building that is about the whole place.
  if (def.isMainBuilding) actions.add(('Workers', () => open(1)));
  // AND EVERY HOUSE OPENS THE POPULATION BUDGET. Keyed on what a building DOES
  // — shelters monsters — not on a list of ids, so a new dwelling in a later
  // era gets the door by being a dwelling (the same rule housingCapacity
  // counts by). The Castle shelters too, so it offers both.
  if (def.sheltersMonsters(ctrl.settlement?.eraIndex ?? 1)) {
    actions.add(('Population', () => open(2)));
  }
  return [
    for (final (label, onTap) in actions)
      _primaryActionButton(label, () {
        Navigator.pop(context);
        onTap();
      }),
  ];
}

/// The prominent form: full width, tall, the settlement's action green, with
/// a chevron so it reads as "this opens something".
///
/// NO emoji (user 2026-07-27) — the label names the feature, and the chevron
/// is the whole affordance.
Widget _primaryActionButton(String label, VoidCallback onTap) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: parchmentButton(),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: FoE.title(
                  size: 16,
                ).copyWith(color: parchmentButtonInk()),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 22,
              color: parchmentButtonInk().withValues(alpha: 0.85),
            ),
          ],
        ),
      ),
    );

/// The building art, free-standing — no tile box behind it (user
/// 2026-07-22). Bottom-anchored in a fixed slot so taller art rises out of
/// the dialog's top edge, exactly like the build-menu cards.
Widget _artPanel(BuildingDef def) => SizedBox(
  // Bigger (user request 2026-08-27), from 140 — Clip.none twice over (here
  // and the scroll view above) is what lets the extra height rise past the
  // dialog's own top edge instead of needing more room reserved for it.
  width: 175,
  // Deliberately much shorter than the art is wide: the sprite is
  // bottom-anchored, so a short slot is what PUSHES it up and out over the
  // dialog's top edge (user 2026-07-22).
  height: 85,
  child: Stack(
    clipBehavior: Clip.none,
    children: [
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        // Standing on its cast shadow — the same look as the build-menu
        // card (user 2026-07-23), one definition in ShadowedBuildingIcon.
        child: Center(
          child: ShadowedBuildingIcon(
            imageUrl: def.imageUrl,
            defId: def.id,
            width: 175,
          ),
        ),
      ),
    ],
  ),
);

// ── Ink on the detail dialog's PARCHMENT surface ──────────
// The dialog wears the build menu's parchment now (user 2026-07-23), so its
// ink is the paper's own dark brown in three weights — the app's white would
// vanish on it, exactly the reverse of the old blue tile.
const Color _dlgInk = kParchmentInk;
final Color _dlgInkSoft = kParchmentInk.withValues(alpha: 0.78);
final Color _dlgInkFaint = kParchmentInk.withValues(alpha: 0.55);

/// The meander band's own ink — as faint as [ParchmentPage.ornament], not
/// [_dlgInkFaint] (that one is for TEXT, and at 0.55 the band would compete
/// with the content it's meant to sit quietly behind).
final Color _dlgOrnament = kParchmentInk.withValues(alpha: 0.22);

/// The warm ACCENT for labels on the parchment (user 2026-07-23) — see
/// [_kDlgAccent]. Buttons keep goldBright: they wear the dark FoE.btn
/// surface, so the light gold still pops there.
const Color _dlgAccent = _kDlgAccent;

/// A system role's contribution. The wording lives in
/// workshop_role_effects.dart, shared with the build menu, the upgrade sheet
/// and the Dev-Mode preview.
///
/// NO GLYPH unless the value needs one to say WHICH system it belongs to
/// (user 2026-07-27: "icon bei der Reduktion löschen (−n%)"). On a worker's
/// row the post above already names the role, and on a single-role building
/// so does the whole dialog — there the 🩹 beside "−25 %" was decoration.
/// Only the Total line of a building with SEVERAL system roles (the Scout
/// Post's travel/carry/goods) keeps it, because there three bare percentages
/// would sit side by side with nothing to tell them apart.
String _systemRoleValue(String res, double power, {bool withGlyph = false}) =>
    withGlyph
    ? '${workshopRoleEffect(res, power)} ${workshopRoleEmoji(res)}'
    : workshopRoleEffect(res, power);

/// One resource/role glyph — kResourceEmoji is the app-wide source, goods
/// bring their own, and the three non-resource role keys get their own icon.
String _resEmoji(String res) => switch (res) {
  WorkshopRole.kConstruction => '🔨',
  WorkshopRole.kCrafting => '⚗️',
  WorkshopRole.kTraining => '🏋️',
  WorkshopRole.kLegendaryBoost => '⭐',
  // ONE table decides (user 2026-07-30) — see resource_icons.dart for why
  // this used to disagree with the header for `fur`.
  _ => resourceEmoji(res),
};

/// A resource key's display NAME (for the row label): a good's own name, the
/// capitalised raw, or a friendly name for the pseudo outputs.
/// Role keys are named by what they DO (shared vocabulary); anything else is
/// a real resource and keeps its own name.
String _resLabel(String res) =>
    workshopRoleName(res) ??
    kGoodsDefs[res]?.name ??
    (res.isEmpty ? 'Resource' : res[0].toUpperCase() + res.substring(1));

/// Production block (user 2026-07-22): the worker-independent BASE line
/// first, then one row per stationed monster with what THAT monster adds on
/// the right, and a "+" under the last worker to post another.
Widget _productionSection(
  SettlementController ctrl,
  PlacedBuilding b,
  BuildingDef def,
  bool functional,
) {
  final creaturesCtrl = CreaturesController();
  // Same math workshopPower uses, scoped to one building: level yield.
  final f = buildingYieldFactor(b.level);
  final rows = <Widget>[];

  // Running per-resource tally: base first, every present worker on top —
  // what the Total line at the foot reports.
  final total = <String, double>{};
  void add(String res, double v) => total[res] = (total[res] ?? 0) + v;

  /// The civil-service / breeder posts, tallied apart from the stockpile:
  /// their power is a fraction or a time cut, so it can neither be added to
  /// nor printed like a resource (see [_systemRoleValue]).
  final systemPower = <String, double>{};

  /// "+4.5/h" and its glyph, SEPARATELY, per produced resource — ONE LINE
  /// EACH (user 2026-07-27: several outputs on a single row ran the card's
  /// whole width and read as one long number). Split rather than one
  /// "+4.5/h 🪵" string (user 2026-08-31: "Alles soll rechts genau
  /// 'gleichbündig' sein") so [headline] can put every row's glyph in the
  /// SAME reserved slot, whether that row has one or not — an inline glyph
  /// pushed its own number left of wherever a glyph-less row's (storage,
  /// housing) landed.
  ///
  /// Construction is counted in BUILD POINTS, not units per hour — the unit
  /// it is authored in and the one a builder's stat is measured in (user
  /// 2026-07-26). Printing it "/h" made a builder's 30 look like 30 wood.
  List<(String text, String icon)> amountsWithIcons(Map<String, double> m) => [
    for (final e in m.entries)
      if (e.value > 0)
        (
          e.key == WorkshopRole.kConstruction
              ? '+${e.value.toStringAsFixed(0)} points'
              : '+${e.value.toStringAsFixed(1)}/h',
          _resEmoji(e.key),
        ),
  ];

  /// The old combined "+4.5/h 🪵" shape, for callers (Total) that are not
  /// yet split into [headline]'s reserved-slot layout.
  List<String> amounts(Map<String, double> m) => [
    for (final a in amountsWithIcons(m)) '${a.$1} ${a.$2}',
  ];

  /// Label left, value(s) right — stacked, right-aligned, one per line. With
  /// more than one line the label rides at the TOP of the stack so it still
  /// reads as that block's heading.
  ///
  /// Pass [icons] (same length as [values]) to put each value's glyph in its
  /// own fixed-width slot AFTER the number instead of inside the string —
  /// otherwise a row with a trailing glyph (production) and one without
  /// (storage, housing) put their NUMBERS at two different right edges even
  /// though the two blocks themselves lined up (user 2026-08-31: "Alles
  /// soll rechts genau 'gleichbündig' sein"). Omit [icons] entirely for the
  /// old behaviour — plain right-aligned text, no reserved slot — where a
  /// value already carries everything it needs inline (Total, Consumes).
  Widget headline(
    String label,
    List<String> values, {
    Color? color,
    List<String?>? icons,
    // A SUB-category row, nested under its own "Production"/"Storage"
    // heading rather than reading as a heading itself (user 2026-09-01:
    // "Wood, stone gold, housing etc. etwas nach innen versetzt und in
    // weiss"). Null/0 keeps every other caller's look — the accent-gold
    // label flush with the card's edge — exactly as before.
    Color? labelColor,
    double indent = 0,
  }) => Padding(
    padding: EdgeInsets.only(left: indent),
    child: Row(
      crossAxisAlignment: values.length > 1
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: FoE.label(size: 12).copyWith(color: labelColor ?? _dlgAccent),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < values.length; i++)
                icons == null
                    ? Text(
                        values[i],
                        textAlign: TextAlign.end,
                        style: FoE.value(
                          size: 12,
                        ).copyWith(color: color ?? _dlgInk),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Flexible, not bare (2026-09-01: a copy of this
                          // exact row in building_upgrade_sheet.dart
                          // overflowed on a narrower card) — shrinks to an
                          // ellipsis instead of running past whatever width
                          // this Expanded actually has.
                          Flexible(
                            child: Text(
                              values[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: FoE.value(
                                size: 12,
                              ).copyWith(color: color ?? _dlgInk),
                            ),
                          ),
                          SizedBox(
                            width: 18,
                            child: i < icons.length && icons[i] != null
                                ? Center(
                                    child: Text(
                                      icons[i]!,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  )
                                : null,
                          ),
                        ],
                      ),
            ],
          ),
        ),
      ],
    ),
  );

  // PAUSED SAYS SO FIRST (user 2026-08-01). The figures below stay — they are
  // what the building WOULD make — and this line is why none of it is
  // happening, in the same place the empty-tank warning lands.
  if (b.isPaused) {
    rows.add(
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          '⏸️ Paused — producing and consuming nothing. Housing and storage '
          'still count.',
          style: FoE.dim(size: 11).copyWith(color: FoE.danger),
        ),
      ),
    );
  }

  // ── Base: what it makes with nobody stationed ──
  // ONLY its authored `production` effects (user 2026-07-25) — the code-side
  // base table, the hall's automatic build points and the house-gold curve
  // are gone, so this panel and the economy read the same numbers.
  final era = ctrl.settlement?.eraIndex ?? 1;
  final base = <String, double>{};
  for (final res in def.effectKeys('production')) {
    final v = def.effectAt('production', res, era, level: b.level);
    if (v != 0) base[res] = (base[res] ?? 0) + v;
  }
  base.forEach(add);
  // A building with no production effect at all (a store, a house) never
  // gets a row here, and neither does one that HAS the effect but makes
  // nothing at this level (user 2026-08-27: "Ressource ist null, daher
  // soll es nicht angezeigt werden") — an empty "Resource —" line is not
  // an effect, it is the absence of one. "offline" still shows: that is
  // real information about a production effect the building DOES have,
  // just currently blocked.
  final storageKeys = def.effectKeys('storage').toList();
  final hasProduction = def.effectKeys('production').isNotEmpty;
  // "Production" is the CATEGORY heading, same shape as "Storage" below it
  // — not a row's own label any more (user 2026-09-01, the Castle: "Zudem
  // sind Production und Storage Überkategorien. Wood Stone Gold etc.
  // Unterkategorien. Diese sollten unter Production auch noch stehen" —
  // and "Resource in Production umbenennen"). A multi-resource building
  // used to merge every output into ONE row labelled the generic
  // "Resource", with each value line carrying its own icon; now every
  // resource gets its OWN named row under the "Production" heading,
  // exactly like Wood/Stone/Gold already do under "Storage".
  if (hasProduction && (base.isNotEmpty || !functional)) {
    rows.add(
      Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 2),
        child: Text(
          'Production',
          style: FoE.label(size: 12).copyWith(color: _dlgAccent),
        ),
      ),
    );
    // Highest producer first (user 2026-09-01: "nach Produktion ordnen,
    // höchste Produktion immer oben") — not the arbitrary order
    // effectKeys('production') happened to author them in.
    final keys =
        (base.isNotEmpty ? base.keys : def.effectKeys('production')).toList()
          ..sort((a, b) => (base[b] ?? 0).compareTo(base[a] ?? 0));
    for (final key in keys) {
      final v = base[key] ?? 0;
      rows.add(
        headline(
          _resLabel(key),
          [
            functional
                ? (key == WorkshopRole.kConstruction
                      ? '+${v.toStringAsFixed(0)} points'
                      : '+${v.toStringAsFixed(1)}/h')
                : 'offline',
          ],
          icons: [functional ? _resEmoji(key) : null],
          color: !functional ? FoE.danger : _dlgInk,
          labelColor: Colors.white,
          indent: 12,
        ),
      );
    }
  }
  // ── What it can HOLD ──
  // One heading, then the resource and the bare number (user 2026-07-30:
  // "«Ressource» zu «Storage» ändern, dafür überall sonst storage löschen" +
  // "Gib nur die Zahl, ohne Max und ohne Icon"). It used to repeat
  // "Storage · " on every row and add "max" and a glyph to every value —
  // four ways of saying the same thing, four times over.
  if (storageKeys.isNotEmpty) {
    rows.add(
      Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 2),
        child: Text(
          buildingEffectLabel('storage'),
          style: FoE.label(size: 12).copyWith(color: _dlgAccent),
        ),
      ),
    );
    // The staff's room is part of the ceiling this store actually has (user
    // 2026-07-30), so it is part of the number on the row — with the split
    // spelled out, because one of the two halves is a decision you can make
    // right now. PER RESOURCE, because the post's dials are: the same worker
    // can be worth more room in timber than in fur. Only when somebody is
    // really working: the same rule storageCapacity applies (an unconnected
    // store counts for nothing).
    for (final key in storageKeys) {
      if (def.effectEntry('storage', key, era) == null) continue;
      final v = buildingEffectValueAt(def, 'storage', key, era, b.level);
      final posted = functional ? ctrl.storageRoomPosted(b, key) : 0.0;
      rows.add(
        headline(
          _resLabel(key),
          [
            formatBuildingEffect('storage', key, v + posted),
            if (posted > 0)
              '${formatBuildingEffect('storage', key, v)} + '
                  '${shortNumberAbove(posted)} 👷',
          ],
          // Same reserved glyph slot the production row above uses (user
          // 2026-08-31: "Alles soll rechts genau 'gleichbündig' sein"), now
          // filled with the resource's own icon (user 2026-08-31: "Hinter
          // der Zahl beim Storage auch das entsprechende Icon hinzufügen")
          // — the worker-split second line already carries its 👷 inline,
          // so only the main line gets one from here.
          icons: [_resEmoji(key), if (posted > 0) null],
          color: functional ? _dlgInk : _dlgInkFaint,
          labelColor: Colors.white,
          indent: 12,
        ),
      );
    }
  }
  // A production key worth nothing at this level is not one of the
  // building's CURRENT effects, so — unlike the 2026-07-30 version of this
  // card — it gets no row here at all (user 2026-08-27: "Leere und
  // künftige Effekte nicht unter Effects auflisten"). It still shows up on
  // the Upgrade card, which is exactly where "not yet" belongs.
  //
  // Housing capacity (a count, not a /h rate — its own row). No glyph
  // (user 2026-08-27: "Icons bei den Effekts nur für die Ressourcen
  // behalten") — housing is a seat count, not a resource.
  final housing = def.hasEffect('housing', era)
      ? def.effectAt('housing', '', era, level: b.level)
      : def.housingCapacity * f;
  if (housing > 0) {
    rows.add(
      headline(
        'Housing',
        ['${housing.round()}'],
        icons: const [null],
        labelColor: Colors.white,
        indent: 12,
      ),
    );
  }

  // ── EVERY OTHER AUTHORED EFFECT, IN ITS OWN UNIT ──
  // The card printed production and housing and stopped. So a Scout Post —
  // whose entire job is granting expedition slots and hunt lengths — had an
  // Effects card that listed nothing, and the Caravanserai, the Builder Camp
  // and the Healing Hut were all in the same position: the effect worked, it
  // was simply never said out loud.
  //
  // Read through buildingEffectValueAt so a row cannot promise a curve the
  // runtime does not apply, and named/formatted from the shared vocabulary,
  // so a slot count reads "1" and a travel cut reads "−10 % travel". No
  // glyph (user 2026-08-27: "Icons bei den Effekts nur für die Ressourcen
  // behalten") — none of these rows is a resource; that glyph is the
  // production row's alone. Storage has its own grouped block above, so
  // it is left out here.
  //
  // pending rows (worth nothing until a later level) are skipped (user
  // 2026-08-27) — Effects lists what the building does UP TO AND
  // INCLUDING this level, not what it will do.
  for (final row in buildingEffectCardRows(
    def,
    era,
    b.level,
    withEmoji: false,
  )) {
    if (row.pending) continue;
    rows.add(
      headline(
        row.label,
        [row.value],
        icons: const [null],
        color: !functional ? _dlgInkFaint : _dlgInk,
      ),
    );
  }

  // ── Workers: who is posted here and what each one adds ──
  //
  // The section heading only exists to TOTAL several posts. With one post it
  // said exactly what that post's own header says, one line apart — "Workers
  // 1/2" twice over (user 2026-07-26: "doppelt gemoppelt"). A building with
  // one post gets the per-post row alone, and that row is the heading.
  if (def.workshops.length > 1) {
    final totalSlots = def.workshops.fold<int>(
      0,
      (sum, role) => sum + effectiveSlots(role, b.level),
    );
    final totalStaffed = creaturesCtrl.creatures
        .where((c) => c.assignedBuildingId == b.id)
        .length;
    rows
      ..add(const SizedBox(height: 10))
      ..add(
        Row(
          children: [
            Expanded(
              child: Text(
                'Workers',
                style: FoE.label(size: 12).copyWith(color: _dlgAccent),
              ),
            ),
            Text(
              '$totalStaffed/$totalSlots',
              style: FoE.value(
                size: 11,
              ).copyWith(color: functional ? _dlgInk : _dlgInkFaint),
            ),
          ],
        ),
      );
  }
  var trainees = 0;
  // A worker's effective output, summed across every part a COMBINED post
  // splits it into — the same figure the Total line banks per creature.
  double workerOutput(CreatureInstance c, WorkshopRole role) => role
      .contribution((s) => c.statValue(s).toDouble(), b.level)
      .values
      .fold(0.0, (sum, v) => sum + v);
  for (final role in def.workshops) {
    final assigned = creaturesCtrl.creatures
        .where(
          (c) => c.assignedBuildingId == b.id && c.assignedStat == role.stat,
        )
        .toList()
      // Highest producer first (user 2026-09-01: sort the stationed monsters
      // by their effective production/h, same as the Production section
      // above) — not the arbitrary order they happened to get posted in.
      ..sort(
        (x, y) => workerOutput(y, role).compareTo(workerOutput(x, role)),
      );
    final slotCap = effectiveSlots(role, b.level);
    final training = role.resource == WorkshopRole.kTraining;
    // A legendary-boost slot: a stationed legendary multiplies the building's
    // production by (1 + mult), regardless of its stats (user 2026-07-24).
    final boost = role.resource == WorkshopRole.kLegendaryBoost;
    rows.add(const SizedBox(height: 8));
    // The post's header: what it is, how full it is, and the way IN. Editing
    // used to be a separate centred button under the worker list (user
    // 2026-07-26: "das edit menü für die workers soll irgendwie und irgendwo
    // auf die Zeile von Workers und n/n kommen") — the count and the control
    // that changes it belong together, and it saves a whole row per post.
    //
    // It renders for a single-post building too now. It used to be hidden
    // there because the label only repeated the description; carrying the
    // seat count and the edit affordance, it earns its line.
    //
    // And it NAMES the post even when there is only one (user 2026-07-30:
    // every effect a building has must be readable off this card). A bare
    // "Workers 0/1" was the one place the card said nothing: an empty Scout
    // Post never mentioned travel or carrying, an empty Healing Hut never
    // mentioned healing time. What the post feeds is a fact about the
    // BUILDING, so it does not wait for somebody to be posted in it.
    rows.add(
      _workerHeaderRow(
        b: b,
        role: role,
        // JUST THE STAT (user 2026-07-30: "Production -> Fur bitte nur
        // Production schreiben. Bei allen Gebäuden übernehmen"). The row
        // already carries what it makes, twice over: the value on the right
        // ends in the resource's own glyph, and the whole block sits under the
        // heading that names it. "Production → Fur  1/1  +3.5/h 🦫" said "fur"
        // three times on one line.
        //
        // Training and the legendary slot keep their arrow: neither is a
        // stat→resource pair, and their left side alone would name nothing.
        label: _workRoleLabel(role),
        count: '${assigned.length}/$slotCap',
        enabled: functional,
      ),
    );
    // A COMBINED post feeds several systems at once, and its name can only be
    // the trip as a whole ("Expedition", "Caravan"). So it spells the parts
    // out — with no monster posted there is nothing else on the card that
    // would (user 2026-07-30). Parts dialled to zero are left out: they do
    // nothing, and the row is about what this post actually improves.
    if (role.isCombined) {
      final parts = [
        for (final p in role.parts.entries)
          if ((role.mults[p.key] ?? 0) != 0)
            '${workshopRoleEmoji(p.value)} '
                '${workshopRoleName(p.value) ?? p.value}',
      ];
      if (parts.isNotEmpty) {
        rows.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              'Improves ${parts.join(' · ')}',
              style: FoE.dim(size: 10).copyWith(color: _dlgInkSoft),
            ),
          ),
        );
      }
    }
    // No per-post "XP/h each" line (user 2026-08-27: "xp Anzeige löschen,
    // da diese oben bereits angezeigt wird") — the masthead's own XP pill
    // already says it, and it does so once per building instead of once
    // per post.
    if (!functional) {
      rows.add(
        Text(
          'Connect to a road to staff this workshop',
          style: FoE.dim(size: 10).copyWith(color: FoE.danger),
        ),
      );
      continue;
    }
    for (final c in assigned) {
      rows.add(_workerRow(c, role, b.level, training, boost, storageKeys));
      // Only monsters that are actually HERE contribute — same rule
      // _workerRow shows and workshopPower applies.
      // Same predicate the economy uses — the row and the total can no longer
      // disagree about who is working (user 2026-07-30).
      if (!creaturesCtrl.isWorkingNow(c)) continue;
      // A STORE post is already fully stated by the Storage rows above (base
      // + 👷, per resource), and its room has no single figure to total — one
      // dial per resource is the point (user 2026-07-30). Repeating it under
      // "Total" would be the same numbers a second time, and a wrong one: the
      // flat mult is only the fallback.
      if (role.resource == WorkshopRole.kStorageRoom) continue;
      // The runtime's own per-worker formula, including its per-role level
      // scaling — so the displayed output is what banks, and a COMBINED post
      // lands in all three of its buckets here exactly as it does in
      // workshopPower (user 2026-07-29).
      final contribution = role.contribution(
        (s) => c.statValue(s).toDouble(),
        b.level,
      );
      if (training || boost) {
        // Training pays XP; a legendary boost multiplies the building's
        // production — neither adds a resource line here.
        if (training) trainees++;
      } else if (workshopRoleFeedsSystem(role.resource)) {
        // Feeds a SYSTEM, not the storehouse: summed apart so the Total line
        // never reports "+60/h 📦" for a breeder post (user 2026-07-26).
        for (final out in contribution.entries) {
          systemPower[out.key] = (systemPower[out.key] ?? 0) + out.value;
        }
      } else {
        // One formula for every post (2026-07-26). Construction differs only
        // in its UNIT — build points, the same unit the building's passive
        // `production`/`construction` is authored in, so the two share this
        // tally.
        add(role.resource, contribution[role.resource] ?? 0);
      }
    }
    // (The way in moved UP to this post's header row — user 2026-07-26.)
  }

  // ── Was dafür verbrannt wird (user 2026-07-31) ──
  // "clay rafinery soll anzeigen, welche Ressourcen verbraucht werden, um die
  // neue herzustellen"
  //
  // Read off the SAME tally the Total prints, so the two halves of the trade
  // can never drift apart: 7 Timber Frame an hour is 14 wood and 14 stone an
  // hour, and if the rate changes the burn changes with it.
  final recipes = refiningRecipes([
    ...def.effectKeys('production'),
    for (final r in def.workshops) r.resource,
  ]);
  final burn = refiningInputsPerHour({
    for (final id in recipes.keys) id: total[id] ?? 0,
  });
  // AN EMPTY INPUT STOCK PRODUCES NOTHING — the same rule the tick applies
  // (GameEngine._tickGoods caps output at what the inputs cover), and the same
  // lie the energy fix removed: a card promising +7/h with no wood in the yard.
  final res = ctrl.resources;
  final starved = <String>[
    if (res != null)
      for (final input in {for (final r in recipes.values) ...r.keys})
        if (res.amountOf(input) <= 0) input,
  ];

  // ── Total: base + everyone working, the number the settlement banks ──
  if (def.workshops.isNotEmpty) {
    final parts = <String>[
      if (functional && total.isNotEmpty) ...amounts(total),
      if (functional && trainees > 0)
        '🏋️ +${(trainees * kTrainingXpPerHour).toStringAsFixed(0)} XP/h',
      // The system roles' SUMMED power, which is the figure the game really
      // uses — one breeder's 25 % and another's 25 % are not 50 %.
      if (functional)
        for (final e in systemPower.entries)
          _systemRoleValue(e.key, e.value, withGlyph: systemPower.length > 1),
    ];
    // AN EMPTY TANK PRODUCES NOTHING (user 2026-07-30: "fur lodge produziert
    // 3.5 pro Stunde, oben wird mir dies aber nicht angezeigt").
    //
    // The header was right and this card was the one lying: with the energy at
    // zero every rate the settlement banks is multiplied by the "Produktion bei
    // leerem Tank" dial, which is 0 — so the top bar read +0.0/h while this
    // card promised +3.5/h and never mentioned why the two disagreed. The
    // figures above stay (they are what the building CAN do); the Total says
    // what it currently banks, which is nothing.
    final halted =
        functional &&
        parts.isNotEmpty &&
        (b.isPaused || !ctrl.hasEnergy || starved.isNotEmpty);
    final haltReason = b.isPaused
        ? '0/h · paused'
        : !ctrl.hasEnergy
        ? '0/h · no energy'
        : '0/h · no ${starved.map(_resLabel).join(' / ')}';
    rows
      ..add(const SizedBox(height: 8))
      ..add(
        headline(
          'Total',
          !functional
              ? const ['offline']
              : halted
              ? [haltReason]
              : parts.isEmpty
              ? const ['—']
              : parts,
          color: !functional || halted
              ? FoE.danger
              : parts.isEmpty
              ? _dlgInkFaint
              : _dlgInk,
        ),
      );
  }

  if (recipes.isNotEmpty) {
    rows
      ..add(const SizedBox(height: 8))
      ..add(
        headline(
          'Consumes',
          burn.isEmpty
              // Nothing is being made, so nothing is being burned — the RULE
              // is still the point of the building, and it is on the line
              // below.
              ? const ['—']
              : [
                  for (final e in burn.entries)
                    '−${e.value.toStringAsFixed(1)}/h ${_resEmoji(e.key)}',
                ],
          color: burn.isEmpty ? _dlgInkFaint : _dlgInk,
        ),
      );
    // The recipe itself, per unit — what the burn above is derived from, and
    // the only line that is true whether or not anybody is posted here.
    for (final e in recipes.entries) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            '${e.value.entries.map((i) => '${_num(i.value)} '
                '${_resEmoji(i.key)}').join(' + ')}'
            ' → 1 ${_resEmoji(e.key)}',
            textAlign: TextAlign.end,
            style: FoE.dim(size: 11),
          ),
        ),
      );
    }
    if (starved.isNotEmpty && functional) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            'Out of ${starved.map(_resLabel).join(' and ')} — nothing is '
            'being refined.',
            style: FoE.dim(size: 11).copyWith(color: FoE.danger),
          ),
        ),
      );
    }
  }

  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
}

/// A recipe amount: "2", not "2.0".
String _num(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// One stationed monster: sprite + name left, ITS hourly contribution right.
/// Read-only — posting and un-posting both happen in the Edit sheet below
/// (user 2026-07-22, the ✕ per row is gone).
Widget _workerRow(
  CreatureInstance c,
  WorkshopRole role,
  int level,
  bool training, [
  bool boost = false,

  /// The resources this building STORES — what a store post's per-resource
  /// dials are read for (user 2026-07-30). Empty for every other post.
  List<String> storageKeys = const [],
]) {
  final ctrl = CreaturesController();
  // WHY it is not working, in its own words (user 2026-07-30: "wie kann ein
  // Monster als idle angestellt sein? Entweder arbeitet es hier, oder ist nicht
  // in diesem Gebäude").
  //
  // The row said "💤 idle" for two completely different situations — knocked
  // out, and away in the Breeding Hut — which reads as a monster that is
  // employed and lazy. It is neither: it holds the post and cannot man it right
  // now, and WHICH of those it is decides what you would do about it.
  //
  // The post is held ON PURPOSE (the same rule as an expedition, see
  // SettlementController._postedRole): a K.O. lasts minutes and a mating hours,
  // and dropping the job would mean re-staffing every building in the
  // settlement after every lost fight. So the honest fix is to say the reason,
  // not to invent a third state.
  final absence = c.isKo
      ? '💀 K.O. — heal it'
      : ctrl.isBreeding(c.id)
      ? '🥚 in the Breeding Hut'
      : ctrl.isOnExpedition(c.id)
      ? '🎒 away on a trip'
      : c.isHealing
      ? '🩺 under treatment'
      : null;
  final absent = absence != null;
  // Only a LEGENDARY actually boosts; a lesser creature parked here is inert.
  final legendary = c.species?.rarity == CreatureRarity.legendary;
  // Construction is shown in POINTS, not in the build-seconds they convert to
  // (2026-07-26); the formula itself is the same as every other post's.
  final construction = role.resource == WorkshopRole.kConstruction;
  // Everything this one monster is worth here — one entry for an ordinary
  // post, three for the Scout Post's combined one.
  final contribution = role.contribution(
    (s) => c.statValue(s).toDouble(),
    level,
  );
  final contrib = contribution[role.resource] ?? 0;
  // A STORE post is worth a different amount of room in each good it holds
  // (user 2026-07-30), so "the" figure for this worker does not exist — it is
  // one line per resource, named by the resource's own glyph. Read through the
  // role's own formula, so the row cannot disagree with the ceiling above it.
  final storeRoom = role.resource == WorkshopRole.kStorageRoom
      ? [
          for (final key in storageKeys)
            '+${role.storageRoomFor(key, c.statValue(role.stat).toDouble(), level).round()} '
                '${_resEmoji(key)}',
        ]
      : const <String>[];
  final value =
      absence ??
      (storeRoom.isNotEmpty
          ? storeRoom.first
          : boost
          ? (legendary
                ? '⭐ ×${(1 + role.mult).toStringAsFixed(1)}'
                : '⚠ not legendary')
          : training
          ? '+${kTrainingXpPerHour.toStringAsFixed(0)} XP/h'
          : construction
          ? '+${contrib.toStringAsFixed(0)} points 🔨'
          // A system role's contribution is a cut or a bonus, not an hourly
          // amount — and it is only meaningful TOGETHER with its colleagues'
          // (the cut is soft-capped over the summed power), so the row shows
          // what this one monster is worth ALONE and the Total line adds them up.
          : workshopRoleFeedsSystem(role.resource)
          // A combined post says all three of its parts, each with its glyph —
          // that IS the row's content, and one bare percentage could only be one
          // of the three (user 2026-07-29). They are STACKED below, not joined.
          ? workshopPowerLabel(contribution, withGlyph: role.isCombined)
          // Icon after the value (user 2026-07-24).
          : '+${contrib.toStringAsFixed(1)}/h ${_resEmoji(role.resource)}');
  // The stacked form of that same value. A combined post and a STORE post have
  // more than one line; every other row keeps its single [value] string.
  final lines = absent || training || boost || construction
      ? const <String>[]
      : storeRoom.isNotEmpty
      ? storeRoom
      : workshopRoleFeedsSystem(role.resource)
      ? workshopPowerParts(contribution, withGlyph: role.isCombined)
      : const <String>[];
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    // Shared by every building's worker list (user 2026-08-30: "bitte bei
    // allen Gebäuden anpassen") — this one row IS all of them, so the
    // bigger icon and the explicit centring land everywhere at once.
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 32,
          height: 32,
          child: c.imageUrl == null
              ? Icon(Icons.pets, size: 22, color: _dlgAccent)
              : CreatureSprite(
                  url: c.imageUrl!,
                  fallback: Icon(Icons.pets, size: 22, color: _dlgAccent),
                ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            training ? '${c.displayName} · Lv ${c.level}' : c.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FoE.label(size: 12).copyWith(color: _dlgInk),
          ),
        ),
        // Stacked when the post feeds several systems at once, so each
        // amplifier is its own line instead of one long run-on figure
        // (user 2026-07-29). Right-aligned, so the numbers line up under
        // each other rather than drifting with the glyph widths.
        if (lines.length > 1)
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final l in lines)
                Text(l, style: FoE.value(size: 11).copyWith(color: _dlgInk)),
            ],
          )
        else
          Text(
            value,
            style: FoE.value(
              size: 11,
            ).copyWith(color: absent ? _dlgInkFaint : _dlgInk),
          ),
      ],
    ),
  );
}

/// Buy out the rest of a construction. Priced on the REAL remaining wait
/// (see SettlementController.buildSkipCost), so a nearly-finished building
/// is nearly free and one with nobody working on it is not.
Widget _skipBuildButton(BuildContext context, PlacedBuilding b) {
  final ctrl = SettlementController();
  final cost = ctrl.buildSkipCost(b);
  final canPay = ctrl.gold >= cost;
  return _functionBtn(
    canPay
        ? '🪙 Finish now · $cost'
        : '🪙 $cost (you have ${ctrl.gold.toInt()})',
    () async {
      if (!canPay) return;
      Navigator.pop(context);
      // No pop-up on failure any more (user 2026-08-29: "wirklich alle pop
      // up nachrichten... löschen").
      await ctrl.skipBuildWithGold(b);
    },
  );
}

/// The building's worker-INDEPENDENT outputs at [level] — its `production`
/// effects plus housing capacity: the numbers an upgrade actually moves (user
/// 2026-07-24). Housing uses the sentinel key '__housing' (a count, not a /h
/// rate).
///
/// `construction` STAYS (user 2026-07-26: "das soll die passive Construction
/// sein") — it is real, level-scaled build power, just measured in points; it
/// is only the truly inert keys (crafting/training/legendary slots, which
/// nothing reads worker-free) that are dropped.
Map<String, double> _passiveOutputs(
  SettlementController ctrl,
  BuildingDef def,
  int level,
) {
  final era = ctrl.settlement?.eraIndex ?? 1;
  final f = buildingYieldFactor(level);
  final m = <String, double>{};
  for (final res in def.effectKeys('production')) {
    final v = def.effectAt('production', res, era, level: level);
    if (v != 0) m[res] = (m[res] ?? 0) + v;
  }
  final housing = def.hasEffect('housing', era)
      ? def.effectAt('housing', '', era, level: level)
      : def.housingCapacity * f;
  if (housing > 0) m[kHousingOutputKey] = housing;
  m.removeWhere(
    (k, v) =>
        v <= 0 ||
        k == WorkshopRole.kCrafting ||
        k == WorkshopRole.kTraining ||
        k == WorkshopRole.kLegendaryBoost,
  );
  return m;
}

// ── Level upgrade ─────────────────────────────────────────
/// One "label … now → next 🏠" row of the upgrade table.
///
/// Only ever built for a number the level actually MOVES (user 2026-07-26:
/// "nur anzeigen, wenn es effektiv auch etwas ändert, Stats die gleich
/// bleiben, sollen nicht angezeigt werden") — the caller filters. At max
/// level there is no next value, so the row states the current one.
Widget _upgradeLineRow({
  required String label,
  required String emoji,
  required String now,
  required String next,
  required bool atMax,
  bool onlyNext = false,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 5),
  child: Row(
    children: [
      Text(label, style: FoE.label(size: 12).copyWith(color: _dlgAccent)),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          // [emoji] may be empty — the worker/effect rows name themselves on
          // the left and carry no icon (user 2026-07-27).
          (atMax || onlyNext
                  ? '${onlyNext && !atMax ? next : now} $emoji'
                  : '$now  →  $next $emoji')
              .trimRight(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.end,
          style: FoE.value(size: 12).copyWith(color: _dlgInk),
        ),
      ),
    ],
  ),
);

/// Shows what this level yields, what the next one does to it, the cost and
/// build time, and the upgrade button. See building_definitions' level
/// scaling for the curves behind the numbers.
Widget _upgradeSection(
  BuildContext context,
  SettlementController ctrl,
  PlacedBuilding b,
  BuildingDef def,
) {
  final atMax =
      b.level >= maxBuildingLevelFor(def, ctrl.settlement?.eraIndex ?? 1);
  final target = b.level + 1;
  final stock = ctrl.resources?.asMap ?? {};
  final afford = !atMax && def.canAffordAt(target, stock);

  // The EFFECTIVE outputs this level vs the next (user 2026-07-24: show the
  // concrete numbers, not a % increase). Housing rides the '__housing' key.
  final now = _passiveOutputs(ctrl, def, b.level);
  final next = _passiveOutputs(ctrl, def, target);
  final outKeys = buildingOutputOrder(def, {...now.keys, ...next.keys});
  String fmtOut(String k, double? v) {
    final val = v ?? 0;
    if (k == kHousingOutputKey) return val.round().toString();
    // Passive construction is points, like a builder's stat (2026-07-26).
    if (k == WorkshopRole.kConstruction) {
      return '${val.toStringAsFixed(0)} points';
    }
    return '${val.toStringAsFixed(1)}/h';
  }

  // What a level does to the WORK POSTS (a production building's whole
  // output rides on these) AND to every other authored effect — a Builder
  // Camp's "+1 build site at level 3" used to be nowhere in this panel, so a
  // level whose entire point was that bonus looked like it bought nothing
  // (user 2026-07-26).
  final era = ctrl.settlement?.eraIndex ?? 1;
  final workLines = [
    ...workshopUpgradeLines(def, b.level, target),
    ...buildingEffectUpgradeLines(def, b.level, target, era),
  ];

  // ONLY what the level moves (user 2026-07-26: "nur anzeigen, wenn es
  // effektiv auch etwas ändert, Stats die gleich bleiben, sollen nicht
  // angezeigt werden"). A "5 → 5" row costs a line of the panel to say
  // nothing, and three of them bury the one number that did change.
  //
  // At MAX level there is no next value to compare against, so the panel
  // keeps stating what the building currently yields.
  final movedKeys = atMax
      ? outKeys
      : [
          for (final k in outKeys)
            if ((now[k] ?? 0) != (next[k] ?? 0)) k,
        ];
  final movedWork = atMax
      ? const <UpgradeLine>[]
      : workLines.where((l) => l.changed).toList();

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // One row per output, current → next, in the same table shape as the
        // Base/Total lines above ("Output %" removed, user 2026-07-24).
        // Same shape as the Effects card (user 2026-07-24): the resource/
        // effect label on the LEFT, the numbers (now → next) then the icon on
        // the far RIGHT.
        for (final k in movedKeys)
          _upgradeLineRow(
            label: k == kHousingOutputKey ? 'Housing' : _resLabel(k),
            emoji: k == kHousingOutputKey ? '🏠' : _resEmoji(k),
            now: fmtOut(k, now[k]),
            next: fmtOut(k, next[k]),
            atMax: atMax,
            // Just the new number (user request) — the old value cost a
            // reader two numbers to find the one that changed.
            onlyNext: true,
          ),
        // Worker slots and per-worker yield, after the outputs: the outputs
        // are WHAT it makes, these are what makes them.
        for (var i = 0; i < movedWork.length; i++) ...[
          // The group heading, printed once when it changes — "Storage" over
          // its per-resource rows (user 2026-07-30).
          if (movedWork[i].group != null &&
              (i == 0 || movedWork[i - 1].group != movedWork[i].group))
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 3),
              child: Text(
                movedWork[i].group!,
                style: FoE.label(size: 12).copyWith(color: _dlgAccent),
              ),
            ),
          _upgradeLineRow(
            label: movedWork[i].label,
            // NO trailing icon here (user 2026-07-27: "icons rechts entfernen
            // für xp und workers"). A resource row needs its emoji — that is
            // what says WHICH resource — but "Workers" and "XP" already say
            // what they are on the left, so the glyph was decoration.
            emoji: '',
            now: movedWork[i].now,
            next: movedWork[i].next,
            atMax: false,
            onlyNext: movedWork[i].onlyNext,
          ),
        ],
        // With everything filtered out the panel would be a bare button, and
        // "no rows" reads as a rendering fault rather than as an answer.
        if (!atMax && movedKeys.isEmpty && movedWork.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(
              'This level changes no values — only the cost.',
              style: FoE.dim(size: 11).copyWith(color: _dlgInkSoft),
            ),
          ),
        const SizedBox(height: 8),
        if (atMax)
          Text(
            'Maximum level reached.',
            style: FoE.dim(size: 11).copyWith(color: _dlgInkSoft),
          )
        else
          // Cost and build time live INSIDE the button (user 2026-07-22) —
          // the price is part of the offer, not a caption above it.
          GestureDetector(
            onTap: afford ? () => _doUpgrade(context, ctrl, b.id) : null,
            // No more blanket dimming/reddening when it can't afford (user
            // 2026-09-01: "wenn upgrade nicht geht, nur das rot einfärben,
            // welches fehlt" — the whole line used to fade AND turn red
            // together, so "too little wood" looked identical to "too
            // little wood and stone and gold." Only the actual short
            // resource(s) turn red now; the button's own active/inactive
            // decoration is still the tap cue.
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              alignment: Alignment.center,
              decoration: parchmentButton(active: afford),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Upgrade',
                    style: FoE.label(
                      size: 13,
                    ).copyWith(color: parchmentButtonInk(active: afford)),
                  ),
                  const SizedBox(height: 3),
                  _costLine(
                    def.resourceCostAt(target),
                    stock,
                    fmtDuration(def.constructionSecondsAt(target)),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

Future<void> _doUpgrade(
  BuildContext context,
  SettlementController ctrl,
  String buildingId,
) async {
  final err = await ctrl.upgradeBuilding(buildingId);
  if (!context.mounted) return;
  // No pop-up on failure any more (user 2026-08-29: "wirklich alle pop up
  // nachrichten... löschen") — the dialog just stays open.
  if (err == null) {
    Navigator.pop(context); // close dialog; the building is now rebuilding
  }
}

/// "🪵 320  🪨 96  ⏱ 2m" — resource cost and build time, each figure its own
/// [Text] rather than one joined string (user 2026-09-01: "wenn upgrade
/// nicht geht, nur das rot einfärben, welches fehlt" — only whichever
/// resource the stockpile actually falls short on turns red; a resource
/// that's fully paid for, and the build time, read in the button's normal
/// ink either way).
Widget _costLine(
  Map<String, double> cost,
  Map<String, double> stock,
  String buildTime,
) {
  const base = {'wood': '🪵', 'stone': '🪨', 'gold': '🪙'};
  final ink = parchmentButtonInk(active: true);
  return Wrap(
    alignment: WrapAlignment.center,
    spacing: 8,
    runSpacing: 2,
    children: [
      for (final e in cost.entries)
        Text(
          '${base[e.key] ?? kGoodsDefs[e.key]?.emoji ?? e.key} '
          '${e.value.ceil()}',
          style: FoE.dim(
            size: 10,
          ).copyWith(color: (stock[e.key] ?? 0) < e.value ? FoE.danger : ink),
        ),
      Text('⏱ $buildTime', style: FoE.dim(size: 10).copyWith(color: ink)),
    ],
  );
}

Widget _functionBtn(String label, VoidCallback onTap) => SizedBox(
  width: double.infinity,
  child: GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: parchmentButton(),
      alignment: Alignment.center,
      child: Text(
        label,
        style: FoE.label(size: 13).copyWith(color: parchmentButtonInk()),
      ),
    ),
  ),
);

// ── Worker assignment (creature economy) ──────────────────
// Each workshop role is staffed by SPECIFIC creatures; a role's output is
// the sum of its workers' civilian stat, so the player picks who works where.
// The roster itself lives in _productionSection now — what's left here is the
// recipe picker and the notes about the crew as a whole.
Widget _workshopExtras(PlacedBuilding b, BuildingDef def, bool functional) {
  final ctrl = CreaturesController();
  final posted = ctrl.creatures.where((c) => c.assignedBuildingId == b.id);
  // Counts who's actually HERE — away creatures earn no XP either
  // (accruePassiveXp uses the same rule).
  final stationed = posted.where(ctrl.isWorkingNow).length;
  final away = posted.length - stationed;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // The recipe picker used to live here as a Wrap of chips. It is the
      // Crafting screen now, opened by this dialog's own primary action —
      // see _primaryAction (user 2026-07-29).
      // The XP rate itself now sits next to the Workers heading; only the
      // "nobody is earning it" case still needs saying.
      if (stationed > 0 && !functional)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            'No road connection — nobody here is working, or earning XP.',
            style: FoE.dim(size: 11).copyWith(color: FoE.danger),
          ),
        ),
      if (away > 0)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '🎒 $away on expedition — post${away > 1 ? 's' : ''} held, '
            'no output until they return',
            style: FoE.dim(size: 10).copyWith(color: _dlgAccent),
          ),
        ),
    ],
  );
}

/// A work post's header: what it is, how full it is, and the way in.
///
/// The WHOLE row opens the assign sheet (user 2026-07-26) — the seat count
/// and the control that changes it were a row apart, with a centred "Edit"
/// button under the worker list. Tapping the count is what anyone tries
/// first anyway, and every post gets a row back.
///
/// [enabled] is false for an unconnected building: there is nothing to edit
/// until it has a road, so the row says the count and stays inert.
// No per-role "+" any more, and the row itself no longer opens the
// picker (user 2026-08-27: "anstelle des '+' Buttons zwischen der
// effects und upgrade box einen 'Manage' Button") — ONE button between
// the Effects and Upgrade cards now owns staffing for every role, so
// this row is purely a readout: what the post is, how full it is.
Widget _workerHeaderRow({
  required PlacedBuilding b,
  required WorkshopRole role,
  required String label,
  required String count,
  required bool enabled,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 4),
  child: Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: FoE.label(
            size: 11,
          ).copyWith(color: enabled ? _dlgAccent : _dlgInkFaint),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      const SizedBox(width: 8),
      Text(
        count,
        style: FoE.value(
          size: 12,
        ).copyWith(color: enabled ? _dlgInk : _dlgInkFaint),
      ),
    ],
  ),
);

void _openAssignPicker(
  BuildContext context,
  SettlementController ctrl,
  PlacedBuilding b,
  WorkshopRole role,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => AssignWorkersSheet(ctrl: ctrl, building: b, role: role),
);

/// Training and the legendary slot keep their arrow: neither is a
/// stat→resource pair, and their left side alone would name nothing.
/// Shared between the Effects card's read-only post rows and the
/// Manage picker, so the two cannot drift apart on what a post is called.
String _workRoleLabel(WorkshopRole role) => switch (role.resource) {
  WorkshopRole.kTraining => 'Training → XP',
  WorkshopRole.kLegendaryBoost =>
    '⭐ Legendary → ×${(1 + role.mult).toStringAsFixed(1)}',
  _ => role.stat.label,
};

/// ONE door into staffing, for every post a building has (user 2026-08-27:
/// "anstelle des '+' Buttons zwischen der effects und upgrade box einen
/// 'Manage' Button"). A single-post building (almost all of them) goes
/// straight to that post's picker; a combined one (the Scout Post, the
/// Storehouse) offers the roles to choose from first.
void _manageWorkers(
  BuildContext context,
  SettlementController ctrl,
  PlacedBuilding b,
  BuildingDef def,
) {
  if (def.workshops.length == 1) {
    _openAssignPicker(context, ctrl, b, def.workshops.first);
    return;
  }
  final creaturesCtrl = CreaturesController();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => ParchmentSheet(
      title: 'Manage Work',
      initialSize: 0.4,
      minSize: 0.3,
      maxSize: 0.7,
      builder: (_, scrollCtrl) => ListView(
        controller: scrollCtrl,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        children: [
          for (final role in def.workshops)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _openAssignPicker(context, ctrl, b, role);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: ParchmentSheet.card,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _workRoleLabel(role),
                          style: FoE.label(
                            size: 13,
                          ).copyWith(color: ParchmentSheet.ink),
                        ),
                      ),
                      Text(
                        '${creaturesCtrl.creatures.where((c) => c.assignedBuildingId == b.id && c.assignedStat == role.stat).length}/${effectiveSlots(role, b.level)}',
                        style: FoE.value(
                          size: 13,
                        ).copyWith(color: ParchmentSheet.inkSoft),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: ParchmentSheet.inkFaint,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

// ── Live build countdown ───────────────────────────────────
// showDialog builds its content once — the Dialog's own subtree never
// rebuilds on the controller's periodic ticks, so a plain Text would freeze
// at whatever the progress was when the dialog opened.
//
// Rather than decrementing a local counter once per second (which drifts
// against the controller's own 5s-authoritative tick — Dart's Timer.periodic
// can fire late under jank, and each resync would then have to "catch up",
// visibly jumping), this widget anchors to an absolute point in time
// (constructionSecondsBuilt as of energy.lastUpdatedAt) and recomputes the
// displayed value fresh from elapsed wall-clock time on every repaint. A 1s
// Timer only forces a repaint; it never mutates the displayed number itself.
// Resyncing (via ctrl.addListener) just moves the anchor to a newer snapshot
// — since both the anchor and the per-frame formula agree by construction,
// a resync only changes what's on screen if the real rate actually changed.
class _BuildCountdown extends StatefulWidget {
  final SettlementController ctrl;
  final String buildingId;
  const _BuildCountdown({required this.ctrl, required this.buildingId});

  @override
  State<_BuildCountdown> createState() => _BuildCountdownState();
}

class _BuildCountdownState extends State<_BuildCountdown> {
  Timer? _timer;
  bool _queued = false;
  bool _done = false;
  double _requiredGameSeconds = 0;
  // Anchor: authoritative built-seconds + real-worker rate as of _anchorTime.
  double _anchorBuiltGameSeconds = 0;
  double _rateGamePerRealSecond = 0; // 0 = stalled (no build energy)
  DateTime _anchorTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    widget.ctrl.addListener(_resync);
    _resync();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    widget.ctrl.removeListener(_resync);
    _timer?.cancel();
    super.dispose();
  }

  PlacedBuilding? get _building {
    for (final b in widget.ctrl.buildings) {
      if (b.id == widget.buildingId) return b;
    }
    return null;
  }

  void _resync() {
    final b = _building;
    if (b == null || b.isComplete) {
      _timer?.cancel();
      if (mounted) setState(() => _done = true);
      return;
    }
    if (b.isQueued) {
      setState(() => _queued = true);
      return;
    }
    final e = widget.ctrl.energy;
    double rate = 0;
    if (e != null) {
      // buildRatePerHour already includes buildSpeedMultiplier — applying it
      // again here squared the bonus (25x under the jumpstart). An empty tank
      // builds at the floor rate now, not zero (energy boosts, doesn't gate).
      //
      // NO /activeCount either: every site builds at the full rate (user
      // 2026-07-24), which is what tick() and the build menu both do. This
      // countdown was the last place still splitting, so a second site made
      // the first one's ETA silently double.
      rate =
          (widget.ctrl.buildRatePerHour / 3600.0) *
          (e.currentEnergy > 0 ? 1.0 : kEnergyFloorRate);
    }
    setState(() {
      _queued = false;
      _requiredGameSeconds = b.constructionSecondsRequired;
      _anchorBuiltGameSeconds = b.constructionSecondsBuilt;
      _rateGamePerRealSecond = rate;
      _anchorTime = e?.lastUpdatedAt ?? DateTime.now().toUtc();
    });
  }

  // Extrapolates built-seconds forward from the anchor using real elapsed
  // time — the same linear formula GameEngine.tick() uses internally, so
  // this always agrees with the next authoritative tick (up to real rate
  // changes), never an accumulated drift.
  double get _builtNowGameSeconds {
    final elapsed =
        DateTime.now().toUtc().difference(_anchorTime).inMilliseconds / 1000.0;
    final built = _anchorBuiltGameSeconds + _rateGamePerRealSecond * elapsed;
    return built.clamp(0.0, _requiredGameSeconds);
  }

  @override
  Widget build(BuildContext context) {
    if (_done) {
      return Text(
        'Complete!',
        style: FoE.dim(size: 11).copyWith(color: _kDlgAccent),
      );
    }
    final builtNow = _builtNowGameSeconds;
    final pct = _requiredGameSeconds <= 0
        ? 100
        : ((builtNow / _requiredGameSeconds) * 100).toInt();
    final remainingGameSeconds = _requiredGameSeconds - builtNow;
    final secondsLeft = _rateGamePerRealSecond > 0
        ? remainingGameSeconds / _rateGamePerRealSecond
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RecessBar(value: pct / 100.0, color: _kDlgAccent, height: 12),
        const SizedBox(height: 6),
        Text(
          _queued
              ? 'In build queue — waiting for a free slot'
              : secondsLeft == null
              ? '$pct% — no build energy'
              : '$pct%  ·  ${fmtDuration(secondsLeft)} remaining',
          // On the dialog's parchment recess — the warm accent reads, the app's
          // light gold does not.
          style: FoE.dim(size: 11).copyWith(color: _kDlgAccent),
        ),
      ],
    );
  }
}
