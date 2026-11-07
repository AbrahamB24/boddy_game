import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;

import '../../../core/theme/foe_theme.dart';
import '../../../core/theme/cream_kit.dart';
import '../../../core/theme/fachwerk.dart';
import '../../../core/ui/snack.dart';
import '../../../core/ui/duration_format.dart';
import '../../../core/ui/number_format.dart';
import '../../../core/ui/scroll_cue.dart';
import '../../common/widgets/recess_bar.dart';
import '../../creatures/battle_screen.dart';
import '../../creatures/combat_school_screen.dart';
import '../../creatures/expeditions_screen.dart';
import '../../creatures/hatchery_screen.dart';
import '../../creatures/healing_hut_screen.dart';
import '../../creatures/models/combatant.dart';
import '../../creatures/models/creature_enums.dart'
    show
        CreatureRarity,
        kBuilderCampBuildingId,
        kScoutPostBuildingId,
        kWorkshopBuildingId,
        kCombatSchoolBuildingId,
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
import '../../creatures/widgets/creature_family.dart'
    show CreatureFace, CreatureSeatTile;
import '../../onboarding/intro_flow.dart';
import '../../onboarding/intro_spotlight.dart';
import '../crafting_screen.dart';
import '../data/building_definitions.dart';
import '../data/goods_definitions.dart';
import '../data/resource_icons.dart';
import '../data/workshop_role_effects.dart';
import '../work_screen.dart';
import '../market_screen.dart';
import '../models/placed_building.dart';
import '../settlement_controller.dart';
import '../assign_workers_screen.dart';
import '../widgets/building_icon.dart';
import '../widgets/building_life.dart' show kPausedFilter;
import 'building_upgrade_sheet.dart';
import '../../../core/ui/pressable.dart';
import '../../../core/theme/voxel_kit.dart' show vr;
import '../../../core/theme/voxel_icons.dart';
import '../../../core/ui/game_text.dart';

// Training battle vs. 1-3 random wild creatures near the team's level.
// Lives at the Training Grounds (user decision 2026-07-17, moved off the
// Monsters screen): the place you train is the place you spar.
Future<void> _startTrainingBattle(BuildContext context) async {
  final creatures = CreaturesController();
  final team = creatures.battleTeam();
  if (team.isEmpty) {
    context.snack(
      'Nobody is ready to fight — heal your monsters first.',
      error: true,
    );
    return;
  }
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

// ── Detail dialog ─────────────────────────────────────────
/// The building detail dialog, "Variante 3 · Holz" (user 2026-09-19, picked
/// from ten layouts). Three tiers, top to bottom:
///
///  * a HERO card — art rising out of it, name, level/footprint/state pills,
///    the building's primary actions and the pause switch;
///  * a fixed-height row of two cards, EFFECTS and CREW. They keep the same
///    size whatever the building: the Effects rows flow into two columns (and
///    only then shrink) when there are many, the Crew tiles scale
///    ([_CrewGrid]) so 24 seats and every effect always fit without scrolling;
///  * an UPGRADE bar that never moves — "Lv 4 → Lv 5", what the level brings,
///    the cost inside the button.
///
/// Opened by tapping a building on the settlement map, and (since 2026-08-31)
/// from a building's row in the Management screen's Housing tab — the same
/// dialog either way, just given an explicit [SettlementController] instead of
/// reading it off `widget.ctrl` the way the map's own State used to.
Future<void> showBuildingDetailDialog(
  BuildContext context,
  SettlementController ctrl,
  PlacedBuilding b, {
  // Only the map's own call site passes true — the Builder Camp's "Build"
  // action just closes this dialog to reveal the bottom carousel sitting
  // right underneath it (see that action's own doc comment below), which
  // only exists on the settlement screen. Opened from Housing/Work/a
  // resource tab instead, popping would land back on THAT screen with no
  // carousel to reveal, so the button has to stay hidden there.
  bool onMap = false,
}) {
  final def = kBuildingDefs[b.buildingTypeId]!;
  return showDialog<void>(
    context: context,
    // The map behind goes brown with the kit.
    barrierColor: CreamPalette.dim,
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
        // Guided tutorial (user 2026-09-06): the Healing Hut's empty "+" worker
        // tile is the only lit control in this dialog for as long as this is
        // true — Upgrade and the primary actions are dimmed and dead. Self-
        // clearing: posting a worker here is what advances past assignHealer
        // (see SettlementController.setAssignment), so the NEXT rebuild after
        // a successful assignment already sees a different step and stops
        // restricting anything.
        final healerStep =
            ctrl.introStep == IntroStep.assignHealer &&
            liveB.buildingTypeId == kHealingHutBuildingId;
        // The very next step (user 2026-09-30: "soll ich direkt wieder auf
        // den Healing Hut Detailscreen kommen. Dort kommt ein kurzer Text,
        // dass das Healing Hut nun funktioniert") — same one-lit-control
        // treatment, but the PRIMARY ACTION button is the lit target now,
        // not the (already-filled) crew slot.
        final healStep =
            ctrl.introStep == IntroStep.healStarter &&
            liveB.buildingTypeId == kHealingHutBuildingId;
        // Right after placing the Healing Hut (user 2026-10-01: "Bild 1 noch
        // ein Text hinzufügen, dass Gold den Bau beschleunigt und ich den
        // Bau nun sofort beenden soll") — the buy-out button is the one lit
        // control while this building is still under construction.
        final buildStep =
            ctrl.introStep == IntroStep.buildHealingHut &&
            liveB.buildingTypeId == kHealingHutBuildingId;
        final oneLitControl = healerStep || healStep || buildStep;
        Widget lockable(Widget child) => IgnorePointer(
          ignoring: oneLitControl,
          child: Opacity(opacity: oneLitControl ? 0.35 : 1, child: child),
        );
        final size = MediaQuery.sizeOf(context);
        // The Effects/Crew row is the one thing that must NOT change size from
        // building to building (user 2026-09-19), so its height comes from the
        // screen, not from what is inside.
        final middleH = (size.height - _kDialogChrome - _kArtRise).clamp(
          160.0,
          260.0,
        );
        // A building nobody can work in has no Crew to show (user 2026-09-28:
        // "Castle … Crew gibt es nicht"): its Effects take the whole row instead
        // of sharing it with a card that only says "nobody works here".
        final hasCrew = def.workshops.isNotEmpty;
        final panels = liveB.isComplete
            ? _buildPanels(
                context,
                ctrl,
                liveB,
                def,
                functional,
                spotlightSlot: healerStep,
                // The crew seat a tutorial-tap just filled must stay FILLED
                // (user 2026-10-01: "da man ansonsten das Monster wieder vom
                // Posten lösen könnte") — a tap on it opens the swap picker,
                // which can remove the very worker healStarter is about to
                // test healing. Scoped to healStep, not oneLitControl as a
                // whole: assignHealer's own empty seat must stay tappable,
                // it IS that step's lit control.
                lockAssignedSeats: healStep,
              )
            : null;
        final rawActions = _primaryActions(
          ctrl,
          context,
          liveB,
          def,
          functional,
          onMap: onMap,
        );
        // healStep leaves the primary action (Healing) bright and tappable
        // instead of dimming it like [lockable] dims everything else — it
        // IS the one lit control for this step, not something this step
        // locks away.
        final actions = [
          for (var i = 0; i < rawActions.length; i++)
            healStep && i == 0
                ? KeyedSubtree(
                    key: IntroSpotlightAnchors.of('healing-hut-heal-action'),
                    child: rawActions[i],
                  )
                : lockable(rawActions[i]),
        ];
        // PAUSE, a round button in the hero (user 2026-08-27). Only for
        // buildings that actually RUN something: pausing a house or a store
        // would be a switch with nothing behind it. Taken away for the
        // tutorial's one-lit-control window.
        final pause = liveB.isComplete && _canPause(def) && !oneLitControl
            ? _circleBtn(
                liveB.isPaused ? Icons.play_arrow : Icons.pause,
                () => ctrl.setPaused(liveB.id, !liveB.isPaused),
              )
            : null;
        final upgradeBar = liveB.isComplete && ctrl.isUpgradable(def)
            ? lockable(_upgradeBar(context, ctrl, liveB, def))
            : null;
        final notes = liveB.isComplete && def.workshops.isNotEmpty
            ? _crewNotes(liveB, def, functional)
            : null;
        return PopScope(
          canPop: !oneLitControl,
          child: Dialog(
            backgroundColor: Colors.transparent,
            // The app's default DialogTheme draws a faint border around the
            // Dialog's own bounds; this dialog lets the art rise past them
            // (Clip.none), so the shape carries no side.
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            child: Stack(
              // Clip.none twice over (here and in the scroll view): the art is
              // bottom-anchored in its slot and must be free to rise past the
              // top edge, the way the build-menu cards do.
              clipBehavior: Clip.none,
              children: [
                SizedBox(
                  width: (size.width - 28).clamp(360.0, 728.0),
                  // NO PLATE (user 2026-09-18) — the cards stand straight on
                  // the dimmed map, each with its own hard shadow.
                  child: SingleChildScrollView(
                    clipBehavior: Clip.none,
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Guided tutorial: one banner explaining the concept,
                        // right where the player lands after tapping the
                        // spotlit Healing Hut (user 2026-08-24).
                        if (oneLitControl) ...[
                          creamCard(
                            padding: const EdgeInsets.all(10),
                            // Amber underneath instead of tan: the note is the
                            // one thing to read here.
                            deep: CreamPalette.goldDeep,
                            child: Text(
                              healStep
                                  // user 2026-09-30: "ein kurzer Text, dass
                                  // das Healing Hut nun funktioniert und ich
                                  // nun mein Monster heilen soll".
                                  ? 'The Healing Hut is up and running — '
                                        'tap Healing and treat your monster.'
                                  : 'A building only works once it has a '
                                        'worker posted to it — this Healing '
                                        'Hut heals nobody until someone is '
                                        'stationed there. Tap the + under '
                                        'Crew and post a monster to its '
                                        'medicine role.',
                              style: FoE.label(
                                size: 11,
                              ).copyWith(color: kBoxInk),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        // ONE card for hero + content now (user 2026-09-29:
                        // "überall ist noch der Header abgetrennt, dieser
                        // soll aber auch in den gleichen Kasten. Resp. diese
                        // Kasten gibt es nicht mehr" — the hero is chrome-like
                        // but the rule turned out to mean EVERY header, not
                        // just MenuScaffold's). A hairline marks the hero off
                        // from what's below; Effects and Crew, when both
                        // show, stay just a plain [vHairline] apart from
                        // each other — both facets of "what this building
                        // does", never a zone each.
                        pageCard(
                          // Fachwerk (2026-11-02): the timber frame of a
                          // main surface. No roof course here — the
                          // building's own art rises over the top edge.
                          framed: true,
                          // ZERO padding on the shared card: the hero's art
                          // rises past its own top edge into the exact room
                          // [_kArtRise] reserves above it (user 2026-09-28,
                          // "das Gebäudeasset geht oben aus dem Bildschirm
                          // hinaus") — that budget is tuned against this
                          // Column's total height matching what it was
                          // BEFORE hero and content shared one card (a bare
                          // 80 + 10 + middleH + …), so no padding here and a
                          // hairline no taller than the 10px gap it replaces.
                          padding: EdgeInsets.zero,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _heroCard(
                                ctrl,
                                liveB,
                                def,
                                functional,
                                actions: actions,
                                pause: pause,
                              ),
                              // 4.5+1+4.5 = 10px, exactly the gap this
                              // replaces — see the padding note above.
                              hairline(gap: 4.5),
                              if (panels == null)
                                // Under construction: the countdown replaces
                                // both cards — nothing is produced and
                                // nobody works yet.
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      sectionLabel(
                                        'Under construction',
                                        icon: Icons.construction,
                                      ),
                                      const SizedBox(height: 10),
                                      _BuildCountdown(
                                        ctrl: ctrl,
                                        buildingId: liveB.id,
                                      ),
                                    ],
                                  ),
                                )
                              else
                                // NOT dimmed during assignHealer's
                                // one-lit-control window: its empty "+" tile
                                // is the lit control.
                                SizedBox(
                                  height: middleH,
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        flex: 5,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            sectionLabel(
                                              'Effects',
                                              icon: Icons.bolt,
                                            ),
                                            const SizedBox(height: 10),
                                            Expanded(
                                              child: _EffectsBody(
                                                items: panels.effects,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (hasCrew) ...[
                                        vHairline(),
                                        Expanded(
                                          flex: 7,
                                          child: _crewBody(
                                            panels,
                                            def,
                                            functional,
                                            notes == null
                                                ? null
                                                : lockable(notes),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // The bar slot: Upgrade for a finished building, the
                        // buy-out for one still under construction.
                        if (!liveB.isComplete) ...[
                          const SizedBox(height: 10),
                          creamCard(
                            padding: const EdgeInsets.all(8),
                            child: buildStep
                                ? KeyedSubtree(
                                    key: IntroSpotlightAnchors.of(
                                      'healing-hut-skip-build',
                                    ),
                                    child: _skipBuildButton(context, liveB),
                                  )
                                : _skipBuildButton(context, liveB),
                          ),
                        ] else if (upgradeBar != null) ...[
                          const SizedBox(height: 10),
                          upgradeBar,
                        ],
                      ],
                    ),
                  ),
                ),
                // No ✕ (user 2026-07-22) — tapping outside the dialog closes it.
                // Guided tutorial: the one lit control (user 2026-09-06) —
                // see [oneLitControl]/[lockable] above for what it dims.
                if (healerStep)
                  const IntroSpotlightOverlay(
                    anchorName: 'healing-hut-assign-slot',
                    hint: 'Tap the + to post a monster here',
                  ),
                if (buildStep)
                  const IntroSpotlightOverlay(
                    anchorName: 'healing-hut-skip-build',
                    hint: 'Gold speeds up construction — finish it now.',
                  ),
                if (healStep)
                  const IntroSpotlightOverlay(
                    anchorName: 'healing-hut-heal-action',
                    hint: 'Tap Healing to treat your monster.',
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

// ── Dialog measures ─────────────────────────────────────
// A landscape screen is ~430 tall. The Effects/Crew row gets whatever the rest
// leaves: 24 (dialog inset) + 18 (scroll padding) + hero + upgrade bar + the two
// 10px gaps + 4 of slack.
const double _kHeroH = 80;
const double _kBarH = 52;
const double _kDialogChrome = 24 + 18 + _kHeroH + _kBarH + 10 + 10 + 4;

/// How far the art may rise above the hero card's top edge (user 2026-09-28:
/// "das Gebäudeasset geht oben aus dem Bildschirm hinaus"). The art is scaled
/// down to fit its slot plus this much, and the dialog keeps this much room
/// free above the hero, so even the tallest picture stays on screen.
const double _kArtRise = 56;

// ── Detail dialog pieces ─────────────────────────────────
/// The masthead: art rising out of the card's top edge, name, level / footprint
/// / state pills, and at the right the building's primary actions ("what it is
/// FOR" — Healing, Breeding, Market …) and the pause switch.
///
/// Footprint (3×3), level and the XP/state used to sit in a column at the
/// right; as pills under the name they read as the asides they are and free the
/// right edge for the buttons.
Widget _heroCard(
  SettlementController ctrl,
  PlacedBuilding b,
  BuildingDef def,
  bool functional, {
  required List<Widget> actions,
  Widget? pause,
}) {
  // XP/h a worker earns here: the training rate, else the settlement-wide
  // work rate — EVERY building that stations monsters pays it (user
  // 2026-07-30), so this pill is on every staffed building.
  final xpRate = def.workshops.isEmpty
      ? 0.0
      : def.workshops.any((w) => w.resource == WorkshopRole.kTraining)
      ? kTrainingXpPerHour
      : workXpPerHourAt(b.level);
  final (String, Color)? status = !b.isComplete
      ? ('Building', kBoxAccent)
      : !functional
      ? ('No road', FoE.danger)
      : xpRate > 0
      ? ('${xpRate.toStringAsFixed(0)} XP/h', kBoxInk)
      : null;
  return SizedBox(
    height: _kHeroH,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        // Bottom-anchored in a short slot so the taller art rises past the
        // card's top edge (user 2026-07-22).
        // Paused: the art loses its colour, like on the map (user 2026-09-22).
        Positioned(
          left: 12,
          top: 8,
          child: b.isComplete && b.isPaused
              ? ColorFiltered(colorFilter: kPausedFilter, child: _artPanel(def))
              : _artPanel(def),
        ),
        Positioned(
          left: 156,
          right: 12,
          top: 0,
          bottom: 0,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      def.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FoE.title(size: 18).copyWith(color: kBoxInk),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        // The hall shows its level too (user 2026-07-25): it
                        // gains a level with every era.
                        if (ctrl.isUpgradable(def) || def.isMainBuilding)
                          _pill('Lv ${b.level}'),
                        _pill('${def.gridW}×${def.gridH}', icon: Icons.grid_on),
                        // The pause, as a pill of its own beside level and
                        // size — the rest of the dialog says it in words.
                        if (b.isComplete && b.isPaused)
                          _pill('⏸️ Paused', color: CreamPalette.warn),
                        if (status != null) _pill(status.$1, color: status.$2),
                      ],
                    ),
                  ],
                ),
              ),
              for (final a in actions) ...[const SizedBox(width: 8), a],
              if (pause != null) ...[const SizedBox(width: 8), pause],
            ],
          ),
        ),
      ],
    ),
  );
}

/// A small flat label on a card: a tinted rounded plate, no shadow (a shadow
/// would say "you can press this").
Widget _pill(String text, {IconData? icon, Color? color}) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  decoration: BoxDecoration(
    color: CreamPalette.tan.withValues(alpha: 0.18),
    borderRadius: vr(9),
  ),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (icon != null) ...[
        PixelIcon(icon, size: 10, color: kBoxInkSoft),
        const SizedBox(width: 3),
      ],
      Text(
        text,
        style: FoE.value(size: 10.5).copyWith(color: color ?? kBoxInk),
      ),
    ],
  ),
);

/// The kit's round amber button (pause, "what does the max level look like").
Widget _circleBtn(IconData icon, VoidCallback onTap, {double size = 32}) =>
    Pressable(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.35, -0.5),
            colors: [
              Color.lerp(CreamPalette.gold, Colors.white, 0.35)!,
              CreamPalette.gold,
            ],
          ),
          shape: BoxShape.rectangle,
          // Timber ring, like the kit's close button (Fachwerk).
          border: Border.all(color: Fachwerk.timber, width: 2),
          boxShadow: [
            BoxShadow(color: CreamPalette.goldDeep, offset: const Offset(0, 2)),
          ],
        ),
        child: PixelIcon(icon, size: size * 0.55, color: CreamPalette.ink),
      ),
    );

/// The Crew half of the merged Effects/Crew page card: every post's seats as
/// scaling tiles, plus the notes that belong to a staffed building. No card
/// of its own any more — [sectionLabel] and the shared [pageCard] give it its
/// surface (see the call site).
Widget _crewBody(_Panels p, BuildingDef def, bool functional, Widget? notes) {
  final slots = p.posts.fold<int>(0, (s, g) => s + g.slots);
  final staffed = p.posts.fold<int>(0, (s, g) => s + g.workers);
  Widget empty(String text) => Center(
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: FoE.dim(size: 11).copyWith(color: kBoxInkFaint),
    ),
  );
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      sectionLabel(
        'Crew',
        icon: Icons.groups,
        trailing: def.workshops.isEmpty || !functional
            ? null
            : Text(
                '$staffed/$slots',
                style: FoE.value(size: 12).copyWith(color: kBoxInk),
              ),
      ),
      const SizedBox(height: 10),
      Expanded(
        child: def.workshops.isEmpty
            ? empty('Nobody works in this building.')
            : !functional
            ? empty('Connect to a road to staff this workshop.')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _CrewGrid(groups: p.posts)),
                  if (notes != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: notes,
                    ),
                ],
              ),
      ),
    ],
  );
}

/// A building can be paused when it RUNS something: a work post, or a
/// worker-free `production` effect. Everything else has nothing to stop.
bool _canPause(BuildingDef def) =>
    def.workshops.isNotEmpty || def.effectKeys('production').isNotEmpty;

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
  bool onMap = false,
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
    // Where a move is actually learned (user 2026-09-05) — distinct from the
    // Training Grounds' sparring battle below, which practices what a
    // creature already knows.
    kCombatSchoolBuildingId => (
      'Combat School',
      () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CombatSchoolScreen()),
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
      () =>
          pushMenu(context, const HatcheryScreen(startOn: NurseryTab.breeding)),
    ),
    // Incubating and hatching belong to the HATCHERY (user 2026-07-26: "ein
    // ei ausbrüten muss zu der hatchery"), so the building opens them the
    // same way the Breeding Hut opens mating.
    kHatcheryBuildingId => (
      'Hatchery',
      () => pushMenu(context, const HatcheryScreen()),
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
    // The camp houses the builders, so it is a door to the Build picker
    // (user 2026-07-29: "das build menü soll auch durch das build camp
    // aufrufbar sein"). That picker is a permanent bottom carousel on the
    // settlement screen now (2026-09-18), not a screen to push — so this
    // button's whole job is to get this dialog out of the way and reveal
    // the carousel, which is already sitting right there underneath it.
    // Hidden entirely off the map (Housing/Work/a resource tab): popping
    // there would land back on THAT screen with no carousel to reveal.
    kBuilderCampBuildingId when onMap => (
      'Build',
      () => Navigator.of(context).pop(),
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
      () => pushMenu(context, const ExpeditionsScreen()),
    ),
    _ => null,
  };
  final actions = <(String, VoidCallback)>[if (action != null) action];
  // THE TRIBAL CENTER RUNS THE WORKFORCE (user 2026-07-30). Who works where was
  // reachable only from the Manage screen's second tab — a settlement-wide
  // decision with no door in the settlement. The hall is where that door
  // belongs: it is the one building that is about the whole place. Its own
  // screen now (2026-09-11), not a Management tab — Management's tabs went
  // to the expedition target drawers instead.
  if (def.isMainBuilding) {
    actions.add(('Workers', () => pushMenu(context, const WorkScreen())));
  }
  // AND EVERY HOUSE OPENS THE POPULATION BUDGET. Keyed on what a building DOES
  // — shelters monsters — not on a list of ids, so a new dwelling in a later
  // era gets the door by being a dwelling (the same rule housingCapacity
  // counts by). The Castle shelters too, so it offers both.
  if (def.sheltersMonsters(ctrl.dungeonMaxStage)) {
    actions.add((
      'Population',
      () => pushMenu(context, const WorkScreen(startOn: WorkTab.housing)),
    ));
  }
  return [
    for (final (label, onTap) in actions)
      _primaryActionButton(label, () {
        Navigator.pop(context);
        onTap();
      }),
  ];
}

/// A primary action, in the hero: a compact amber pill with a chevron so it
/// reads as "this opens something".
///
/// NO emoji (user 2026-07-27) — the label names the feature, and the chevron
/// is the whole affordance.
Widget _primaryActionButton(String label, VoidCallback onTap) => Pressable(
  onTap: onTap,
  child: Container(
    height: 40,
    padding: const EdgeInsets.only(left: 14, right: 8),
    decoration: goldButton(),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: FoE.title(size: 14).copyWith(color: goldButtonInk()),
        ),
        const SizedBox(width: 2),
        PixelIcon(
          Icons.chevron_right,
          size: 20,
          color: goldButtonInk().withValues(alpha: 0.85),
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
  width: 128,
  // Deliberately much shorter than the art is wide: the sprite is
  // bottom-anchored, so a short slot is what PUSHES it up and out over the
  // dialog's top edge (user 2026-07-22).
  height: 64,
  child: Stack(
    clipBehavior: Clip.none,
    children: [
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        // Standing on its cast shadow — the same look as the build-menu
        // card (user 2026-07-23), one definition in ShadowedBuildingIcon.
        //
        // Tall art is SCALED DOWN into the room the dialog keeps free above the
        // hero ([_kArtRise]); a picture 1.2× as tall as wide just fits, and the
        // scout post (2.2×) shrinks instead of leaving the screen.
        child: SizedBox(
          height: 64 + _kArtRise,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.bottomCenter,
            child: ShadowedBuildingIcon(
              imageUrl: def.imageUrl,
              defId: def.id,
              width: 128,
            ),
          ),
        ),
      ),
    ],
  ),
);

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

// ── Effects + Crew panels ────────────────────────────────
/// One line of the Effects card and the room it takes, so [_EffectsBody] can
/// tell whether they fit one column before laying anything out.
class _EffItem {
  final Widget w;
  final double h;

  /// For a block that WRAPS (the storage chips): its height depends on the width
  /// it is given, so it asks for the full width and says how tall that makes it.
  final double Function(double width)? hAt;
  const _EffItem(this.w, this.h, {this.hAt, this.heading = false});

  /// Starts a new SECTION (Production, Storage, Housing …) — what a wide card
  /// lays out as side-by-side columns instead of one long list.
  final bool heading;

  bool get wide => hAt != null;
  double heightAt(double width) => hAt?.call(width) ?? h;
}

/// One work post's seats: how full it is and a builder per tile (monsters that
/// are posted, then the free seats), each taking the scale [_CrewGrid] chose.
class _PostGroup {
  /// The post's name — printed over its seats when the building has several.
  final String label;
  final int workers;
  final int slots;
  final List<Widget Function(double u)> tiles;

  /// "Improves …" — what a COMBINED post feeds, spelled out because with no
  /// monster posted nothing else on the card says so (user 2026-07-30).
  final String? improves;

  const _PostGroup({
    required this.label,
    required this.workers,
    required this.slots,
    required this.tiles,
    this.improves,
  });
}

class _Panels {
  final List<_EffItem> effects;
  final List<_PostGroup> posts;
  const _Panels(this.effects, this.posts);
}

/// Everything the Effects and Crew cards show, worked out once: the
/// worker-independent BASE lines (production, storage, housing, every other
/// authored effect), each post's seats, and the Total / Consumes lines that
/// tally the base plus everyone working.
_Panels _buildPanels(
  BuildContext context,
  SettlementController ctrl,
  PlacedBuilding b,
  BuildingDef def,
  bool functional, {

  /// The tutorial's one lit control: the first empty seat carries the
  /// spotlight anchor.
  bool spotlightSlot = false,

  /// True while an already-filled seat must not be tappable at all — see the
  /// call site's own doc comment.
  bool lockAssignedSeats = false,
}) {
  final creaturesCtrl = CreaturesController();
  // Same math workshopPower uses, scoped to one building: level yield.
  final f = buildingYieldFactor(b.level);
  final effects = <_EffItem>[];
  void put(
    Widget w,
    double h, {
    double Function(double width)? hAt,
    bool heading = false,
  }) => effects.add(_EffItem(w, h, hAt: hAt, heading: heading));

  /// The height of a headline row with [lines] value lines.
  double lineH(int lines) => 5.0 + 16.0 * lines;

  // Running per-resource tally: base first, every present worker on top —
  // what the Total line at the foot reports.
  final total = <String, double>{};
  void add(String res, double v) => total[res] = (total[res] ?? 0) + v;

  /// The civil-service / breeder posts, tallied apart from the stockpile:
  /// their power is a fraction or a time cut, so it can neither be added to
  /// nor printed like a resource (see [_systemRoleValue]).
  final systemPower = <String, double>{};

  /// "+4.5/h 🪵" per produced resource. Construction is counted in BUILD
  /// POINTS, not units per hour — the unit it is authored in and the one a
  /// builder's stat is measured in (user 2026-07-26).
  List<String> amounts(Map<String, double> m) => [
    for (final e in m.entries)
      if (e.value > 0)
        '${e.key == WorkshopRole.kConstruction ? buildPointsLabel(e.value) : '+${e.value.toStringAsFixed(1)}/h'} '
            '${_resEmoji(e.key)}',
  ];

  /// Label left, value(s) right — stacked, right-aligned, one per line. With
  /// more than one line the label rides at the TOP of the stack so it still
  /// reads as that block's heading.
  ///
  /// Pass [icons] (same length as [values]) to put each value's glyph in its
  /// own fixed-width slot AFTER the number, so a row with a trailing glyph
  /// (production) and one without (storage, housing) put their NUMBERS at the
  /// same right edge (user 2026-08-31: "Alles soll rechts genau
  /// 'gleichbündig' sein"). Omit [icons] for plain right-aligned text.
  Widget headline(
    String label,
    List<String> values, {
    Color? color,
    List<String?>? icons,
    // A SUB-category row, nested under its own "Production"/"Storage"
    // heading rather than reading as a heading itself.
    Color? labelColor,
    double indent = 0,
  }) => Padding(
    padding: EdgeInsets.fromLTRB(indent, 2.5, 0, 2.5),
    child: Row(
      crossAxisAlignment: values.length > 1
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: FoE.label(size: 12).copyWith(color: labelColor ?? kBoxAccent),
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
                        ).copyWith(color: color ?? kBoxInk),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Flexible: shrinks to an ellipsis instead of running
                          // past whatever width this Expanded actually has.
                          Flexible(
                            child: Text(
                              values[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: FoE.value(
                                size: 12,
                              ).copyWith(color: color ?? kBoxInk),
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

  Widget heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 2, bottom: 2),
    child: Text(text, style: FoE.label(size: 12).copyWith(color: kBoxAccent)),
  );

  // PAUSED SAYS SO FIRST (user 2026-08-01). The figures below stay — they are
  // what the building WOULD make — and this line is why none of it is
  // happening, in the same place the empty-tank warning lands.
  if (b.isPaused) {
    put(
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          '⏸️ Paused — producing and consuming nothing. Housing and storage '
          'still count.',
          style: FoE.dim(size: 11).copyWith(color: FoE.danger),
        ),
      ),
      40,
    );
  }

  // ── Base: what it makes with nobody stationed ──
  // ONLY its authored `production` effects (user 2026-07-25) — the code-side
  // base table, the hall's automatic build points and the house-gold curve
  // are gone, so this panel and the economy read the same numbers.
  final era = ctrl.dungeonMaxStage;
  final base = <String, double>{};
  for (final res in def.effectKeys('production')) {
    final v = def.effectAt('production', res, era, level: b.level);
    if (v != 0) base[res] = (base[res] ?? 0) + v;
  }
  base.forEach(add);
  final storageKeys = def.effectKeys('storage').toList();
  final hasProduction = def.effectKeys('production').isNotEmpty;
  // "Production" is the CATEGORY heading, same shape as "Storage" below it;
  // every resource gets its OWN named row under it (user 2026-09-01). A store
  // or a house never gets one, and neither does a building that HAS the effect
  // but makes nothing at this level (user 2026-08-27) — "offline" still shows:
  // that is real information about an effect the building DOES have.
  var productionHeadingShown = false;
  if (hasProduction && (base.isNotEmpty || !functional)) {
    productionHeadingShown = true;
    put(heading('Production'), 19, heading: true);
    // Highest producer first (user 2026-09-01), not authoring order.
    final keys =
        (base.isNotEmpty ? base.keys : def.effectKeys('production')).toList()
          ..sort((a, b) => (base[b] ?? 0).compareTo(base[a] ?? 0));
    for (final key in keys) {
      final v = base[key] ?? 0;
      put(
        headline(
          _resLabel(key),
          [
            functional
                ? (key == WorkshopRole.kConstruction
                      ? buildPointsLabel(v)
                      : '+${v.toStringAsFixed(1)}/h')
                : 'offline',
          ],
          icons: [functional ? _resEmoji(key) : null],
          color: !functional ? FoE.danger : kBoxInk,
          labelColor: kBoxInk,
          indent: 12,
        ),
        lineH(1),
      );
    }
  }
  // ── WORKSHOP-DRIVEN production, stated as a rate (user 2026-09-29:
  // "production pro Statpoint muss bei Effects stehen, da dies der
  // Haupteffekt des Gebäudes ist") ──
  // A plain resource role has no authored baseline `production` effect of
  // its own — the era camps, the shops, every worker-only producer — so
  // without this, EFFECTS said nothing at all about the building's actual
  // job; the rate lived only as a caption on the Crew card below. Read at
  // THIS level, through the same role.mult × levelScale the Crew card's own
  // per-worker figures use.
  final workshopRows = [
    for (final role in def.workshops)
      if (!role.isCombined &&
          role.resource != WorkshopRole.kTraining &&
          role.resource != WorkshopRole.kLegendaryBoost &&
          role.resource != WorkshopRole.kStorageRoom &&
          !workshopRoleFeedsSystem(role.resource))
        MapEntry(role.resource, role.mult * role.levelScale(b.level)),
  ];
  if (functional && workshopRows.isNotEmpty) {
    if (!productionHeadingShown) put(heading('Production'), 19, heading: true);
    for (final e in workshopRows) {
      put(
        headline(
          '${_resLabel(e.key)} Production',
          ['${_num(e.value)} per Statpoint'],
          icons: [_resEmoji(e.key)],
          labelColor: kBoxInk,
          indent: 12,
        ),
        lineH(1),
      );
    }
  }
  // ── What it can HOLD ──
  // One heading, then the resource and the bare number (user 2026-07-30).
  if (storageKeys.isNotEmpty) {
    put(heading(buildingEffectLabel('storage')), 19, heading: true);
    // The staff's room is part of the ceiling this store actually has (user
    // 2026-07-30), so it is part of the number on the row — with the split
    // spelled out, because one of the two halves is a decision you can make
    // right now. Only when somebody is really working: the same rule
    // storageCapacity applies (an unconnected store counts for nothing).
    // A GRID of small tiles — the glyph and the ceiling, with the staff's share
    // in a second line only where somebody is posted (user 2026-09-22: "sobald
    // Monster eingestellt sind, wird nicht mehr alles korrekt angezeigt"). A row
    // per resource with a second line each grew with every good the store holds
    // and shrank the whole card to nothing; tiles wrap to the width they get.
    final tiles = <Widget>[];
    var anyPosted = false;
    for (final key in storageKeys) {
      if (def.effectEntry('storage', key, era) == null) continue;
      final v = buildingEffectValueAt(def, 'storage', key, era, b.level);
      final posted = functional ? ctrl.storageRoomPosted(b, key) : 0.0;
      if (posted > 0) anyPosted = true;
      tiles.add(
        _StorageTile(
          emoji: _resEmoji(key),
          label: _resLabel(key),
          total: formatBuildingEffect('storage', key, v + posted),
          share: posted > 0 ? '+${shortNumberAbove(posted)} 👷' : null,
          dim: !functional,
        ),
      );
    }
    if (tiles.isNotEmpty) {
      final tileH = anyPosted ? _StorageTile.heightWith : _StorageTile.height;
      put(
        Padding(
          padding: const EdgeInsets.only(left: 12, top: 2, bottom: 4),
          child: Wrap(spacing: 6, runSpacing: 5, children: tiles),
        ),
        6 + tileH,
        hAt: (width) {
          final perRow = math.max(
            1,
            ((width - 12 + 6) / (_StorageTile.width + 6)).floor(),
          );
          final rows = (tiles.length / perRow).ceil();
          return 6 + rows * tileH + (rows - 1) * 5;
        },
      );
    }
  }
  // Housing capacity (a count, not a /h rate — its own row). No glyph
  // (user 2026-08-27): housing is a seat count, not a resource.
  final housing = def.hasEffect('housing', era)
      ? def.effectAt('housing', '', era, level: b.level)
      : def.housingCapacity * f;
  if (housing > 0) {
    put(
      headline(
        'Housing',
        ['${housing.round()}'],
        icons: const [null],
        labelColor: kBoxInk,
        indent: 12,
      ),
      lineH(1),
      // Its own section on a wide card (Production | Storage | Housing).
      heading: true,
    );
  }

  // ── EVERY OTHER AUTHORED EFFECT, IN ITS OWN UNIT ──
  // Read through buildingEffectValueAt so a row cannot promise a curve the
  // runtime does not apply, and named/formatted from the shared vocabulary, so
  // a slot count reads "1" and a travel cut reads "−10 % travel". No glyph
  // (user 2026-08-27) — none of these rows is a resource. Pending rows (worth
  // nothing until a later level) are skipped: Effects lists what the building
  // does UP TO AND INCLUDING this level. Storage has its own block above.
  for (final row in buildingEffectCardRows(
    def,
    era,
    b.level,
    withEmoji: false,
  )) {
    if (row.pending) continue;
    put(
      headline(
        row.label,
        [row.value],
        icons: const [null],
        color: !functional ? kBoxInkFaint : kBoxInk,
      ),
      lineH(1),
    );
  }

  // ── Crew: who is posted here, one group per post ──
  var trainees = 0;
  final groups = <_PostGroup>[];
  // A worker's effective output, summed across every part a COMBINED post
  // splits it into — the same figure the Total line banks per creature.
  double workerOutput(CreatureInstance c, WorkshopRole role) => role
      .contribution((s) => c.statValue(s).toDouble(), b.level)
      .values
      .fold(0.0, (sum, v) => sum + v);
  for (final role in def.workshops) {
    // An unconnected building has nobody working: no seats to show, nothing
    // to tally (the Crew card says "connect to a road").
    if (!functional) continue;
    final assigned =
        creaturesCtrl.creatures
            .where(
              (c) =>
                  c.assignedBuildingId == b.id && c.assignedStat == role.stat,
            )
            .toList()
          // Highest producer first (user 2026-09-01).
          ..sort(
            (x, y) => workerOutput(y, role).compareTo(workerOutput(x, role)),
          );
    final slotCap = effectiveSlots(role, b.level);
    final training = role.resource == WorkshopRole.kTraining;
    // A legendary-boost slot: a stationed legendary multiplies the building's
    // production by (1 + mult), regardless of its stats (user 2026-07-24).
    final boost = role.resource == WorkshopRole.kLegendaryBoost;
    // WHAT posting a worker here actually buys — said in plain words, not
    // just left for the tile's own bare glyph+number to imply (user
    // 2026-09-29: "Die per Worker Effekte der Gebäude sollten angegeben
    // werden, so dass der User sofort sieht, was damit gemeint ist"). It used
    // to exist ONLY for a combined post (Scout Post, Caravanserai) — every
    // single-purpose post (the overwhelming majority: Healing Hut, Trading
    // Post, Breeding Hut, Hatchery, Builder Camp, a plain production camp…)
    // had no caption at all UNLESS the building happened to have a SECOND
    // workshop role too (then [several] shows the role's stat name as a
    // header) — so a Healing Hut's tiles read as a bare "−6 % 🩹" with
    // nothing on the card saying that is healing TIME.
    //
    // A COMBINED post feeds several systems at once, and its name can only be
    // the trip as a whole ("Expedition", "Caravan"). Parts dialled to zero are
    // left out: they do nothing.
    String? improves;
    if (role.isCombined) {
      final parts = [
        for (final p in role.parts.entries)
          if ((role.mults[p.key] ?? 0) != 0)
            '${workshopRoleEmoji(p.value)} '
                '${workshopRoleName(p.value) ?? p.value}',
      ];
      if (parts.isNotEmpty) improves = 'Improves ${parts.join(' · ')}';
    } else if (training) {
      improves = '🏋️ Trains for XP — produces nothing here';
    } else if (boost) {
      improves = '⭐ Boosts the WHOLE building\'s output';
    } else if (role.resource == WorkshopRole.kStorageRoom) {
      improves = '🏚 Adds room in this store';
    } else if (workshopRoleFeedsSystem(role.resource)) {
      final name = workshopRoleName(role.resource) ?? role.resource;
      improves = 'Improves ${workshopRoleEmoji(role.resource)} $name';
    } else {
      // The EXACT rate, not just the resource's name (user 2026-09-29: "Wood
      // Production per Statpoint  1.1. So sieht man genau, was wirklich
      // produziert wird") — the number every worker tile below is computed
      // from: stat × this = the tile's own "+N/h" figure, at THIS level.
      final perPoint = role.mult * role.levelScale(b.level);
      improves =
          '${resourceName(role.resource)} Production per Statpoint   '
          '${_num(perPoint)}';
    }
    final free = (slotCap - assigned.length).clamp(0, 1 << 20);
    groups.add(
      _PostGroup(
        label: _workRoleLabel(role),
        workers: assigned.length,
        slots: slotCap,
        improves: improves,
        tiles: [
          for (final c in assigned)
            (u) => _workerTile(
              c,
              role,
              b.level,
              training,
              boost,
              storageKeys,
              u: u,
              onTap: lockAssignedSeats
                  ? null
                  : () =>
                        _openAssignPicker(context, ctrl, b, role, swapId: c.id),
            ),
          for (var i = 0; i < free; i++)
            (u) => _emptyWorkerTile(
              u: u,
              onTap: () => _openAssignPicker(context, ctrl, b, role),
              // Only the first free seat is the lit control while the tutorial
              // walks the player through posting a worker.
              anchorKey: spotlightSlot && i == 0
                  ? IntroSpotlightAnchors.of('healing-hut-assign-slot')
                  : null,
            ),
        ],
      ),
    );
    for (final c in assigned) {
      // Same predicate the economy uses — the row and the total can no longer
      // disagree about who is working (user 2026-07-30).
      if (!creaturesCtrl.isWorkingNow(c)) continue;
      // A STORE post is already fully stated by the Storage rows above (base
      // + 👷, per resource), and its room has no single figure to total.
      if (role.resource == WorkshopRole.kStorageRoom) continue;
      // The runtime's own per-worker formula, including its per-role level
      // scaling — so the displayed output is what banks.
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
        add(role.resource, contribution[role.resource] ?? 0);
      }
    }
  }

  // Energy scales every rate here the SAME way GameEngine.hourlyRates scales
  // the header's own numbers (user 2026-09-14), so the two never disagree.
  //
  // Only what is PRODUCED: build points and the system roles' time cuts run in
  // real time (user 2026-09-28: "10h sind nicht wirklich 10h").
  final energyRate = ctrl.energyMultiplier;
  if (energyRate != 1.0) {
    for (final k in total.keys.toList()) {
      if (k == WorkshopRole.kConstruction) continue;
      total[k] = total[k]! * energyRate;
    }
  }

  // ── What is burned for it (user 2026-07-31) ──
  // Read off the SAME tally the Total prints, so the two halves of the trade
  // can never drift apart.
  final recipes = refiningRecipes([
    ...def.effectKeys('production'),
    for (final r in def.workshops) r.resource,
  ]);
  final burn = refiningInputsPerHour({
    for (final id in recipes.keys) id: total[id] ?? 0,
  });
  // AN EMPTY INPUT STOCK PRODUCES NOTHING — the same rule the tick applies
  // (GameEngine._tickGoods caps output at what the inputs cover).
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
    // THE TOP BAR AND THIS CARD MUST AGREE (user 2026-07-30): low energy shows
    // up as a reduced (not zeroed) Total.
    // An EMPTY energy pool stops everything, and then every figure above is 0 —
    // which read as a bare "—" (user 2026-09-28: the Builder Camp's Effects were
    // "-" with a monster posted). Say WHY instead.
    // Only PRODUCTION (and passive XP) depends on energy — build points and the
    // system roles' cuts run in real time — so a builder or a breeder is never
    // "halted" by an empty pool.
    final noEnergy = ctrl.energyMultiplier <= 0;
    final crewWorking =
        total.keys.any((k) => k != WorkshopRole.kConstruction) || trainees > 0;
    final halted =
        functional &&
        (parts.isNotEmpty || (noEnergy && crewWorking)) &&
        (b.isPaused || starved.isNotEmpty || (noEnergy && crewWorking));
    final haltReason = b.isPaused
        ? '0/h · paused'
        : starved.isNotEmpty
        ? '0/h · no ${starved.map(_resLabel).join(' / ')}'
        : '0/h · no energy';
    // A builder's whole point is the build time it takes off, so that line is
    // ALWAYS there — "0 % time" with nobody posted, never a dash.
    final isBuilder = def.workshops.any(
      (w) => w.resource == WorkshopRole.kConstruction,
    );
    final values = !functional
        ? const ['offline']
        : halted
        ? [haltReason]
        : parts.isEmpty
        ? [
            isBuilder
                ? '${buildPointsLabel(0)} ${_resEmoji(WorkshopRole.kConstruction)}'
                : '—',
          ]
        : parts;
    put(const SizedBox(height: 6), 6);
    put(
      headline(
        'Total',
        values,
        color: !functional || halted
            ? FoE.danger
            : parts.isEmpty && !isBuilder
            ? kBoxInkFaint
            : kBoxInk,
      ),
      lineH(values.length),
    );
  }

  if (recipes.isNotEmpty) {
    put(const SizedBox(height: 6), 6);
    put(
      headline(
        'Consumes',
        burn.isEmpty
            // Nothing is being made, so nothing is being burned — the RULE
            // is still the point of the building, and it is on the line below.
            ? const ['—']
            : [
                for (final e in burn.entries)
                  '−${e.value.toStringAsFixed(1)}/h ${_resEmoji(e.key)}',
              ],
        color: burn.isEmpty ? kBoxInkFaint : kBoxInk,
      ),
      lineH(burn.isEmpty ? 1 : burn.length),
    );
    // The recipe itself, per unit — the only line that is true whether or not
    // anybody is posted here.
    for (final e in recipes.entries) {
      put(
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            '${e.value.entries.map((i) => '${_num(i.value)} '
                '${_resEmoji(i.key)}').join(' + ')}'
            ' → 1 ${_resEmoji(e.key)}',
            textAlign: TextAlign.end,
            style: FoE.dim(size: 11).copyWith(color: kBoxInkSoft),
          ),
        ),
        19,
      );
    }
    if (starved.isNotEmpty && functional) {
      put(
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            'Out of ${starved.map(_resLabel).join(' and ')} — nothing is '
            'being refined.',
            style: FoE.dim(size: 11).copyWith(color: FoE.danger),
          ),
        ),
        34,
      );
    }
  }

  return _Panels(effects, groups);
}

/// The Effects card's body. One column while everything fits; when it does not,
/// the plain rows split into TWO columns (at the row boundary nearest the
/// middle) while the wrapping blocks — the storage tiles — keep the full width;
/// and if even that is too tall the card SCROLLS, with a "more" cue, instead of
/// shrinking every line to a size nobody can read (user 2026-09-22: the
/// Storehouse "wird nicht mehr alles korrekt angezeigt, da es zu wenig Platz
/// hat"). "Alle Effekte" (user 2026-09-19) still holds: nothing is dropped.
class _EffectsBody extends StatelessWidget {
  final List<_EffItem> items;
  const _EffectsBody({required this.items});

  static const double _gap = 16;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final w = c.maxWidth;
      double sumAt(Iterable<_EffItem> l, double width) =>
          l.fold(0.0, (s, i) => s + i.heightAt(width));

      Widget column(List<_EffItem> l) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final i in l) i.w],
      );

      final one = sumAt(items, w);
      if (one * 1.06 <= c.maxHeight || items.length < 2) {
        return _cue(column(items), one > c.maxHeight);
      }

      // A WIDE card (a building with no Crew beside it — the Castle, a house)
      // lays its SECTIONS side by side, Production | Storage | Housing, so the
      // whole card reads at a glance without scrolling (user 2026-09-28: "Castle
      // effects neu gestalten, so dass alles gut sichtbar ist, ohne zu scrollen").
      if (w >= 520) {
        final sections = <List<_EffItem>>[];
        for (final i in items) {
          if (i.heading || sections.isEmpty) sections.add([]);
          sections.last.add(i);
        }
        if (sections.length >= 2) {
          final cols = math.min(3, sections.length);
          final colW = (w - _gap * (cols - 1)) / cols;
          final heights = [for (final s in sections) sumAt(s, colW)];
          final target = heights.fold(0.0, (a, b) => a + b) / cols;
          final columns = <List<_EffItem>>[[]];
          var acc = 0.0;
          for (var i = 0; i < sections.length; i++) {
            if (columns.last.isNotEmpty &&
                columns.length < cols &&
                acc + heights[i] / 2 > target) {
              columns.add([]);
              acc = 0;
            }
            columns.last.addAll(sections[i]);
            acc += heights[i];
          }
          final tallest = columns
              .map((l) => sumAt(l, colW))
              .reduce((a, b) => math.max(a, b));
          if (tallest * 1.08 + 2 <= c.maxHeight) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var k = 0; k < columns.length; k++) ...[
                  if (k > 0) const SizedBox(width: _gap),
                  Expanded(child: column(columns[k])),
                ],
              ],
            );
          }
        }
      }

      // Two columns: consecutive plain rows are split in half side by side; a
      // wrapping block breaks the run and spans the full width.
      final colW = (w - _gap) / 2;
      final segments = <Widget>[];
      var twoH = 0.0;
      var run = <_EffItem>[];
      void flush() {
        if (run.isEmpty) return;
        final total = sumAt(run, colW);
        var cut = run.length;
        if (run.length > 1) {
          var acc = 0.0;
          cut = run.length - 1;
          for (var i = 0; i < run.length; i++) {
            if (acc + run[i].h / 2 >= total / 2) {
              cut = i.clamp(1, run.length - 1);
              break;
            }
            acc += run[i].h;
          }
        }
        final left = run.sublist(0, cut), right = run.sublist(cut);
        twoH += math.max(sumAt(left, colW), sumAt(right, colW));
        segments.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: colW, child: column(left)),
              const SizedBox(width: _gap),
              SizedBox(width: colW, child: column(right)),
            ],
          ),
        );
        run = [];
      }

      for (final i in items) {
        if (i.wide) {
          flush();
          twoH += i.heightAt(w);
          segments.add(i.w);
        } else {
          run.add(i);
        }
      }
      flush();

      final body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: segments,
      );
      // Whichever layout is shorter; if it still does not fit, it scrolls.
      // The same margin the single column gets, plus a little (the Castle's
      // full-width Effects overflowed by 4 px at a 2 % margin: the row
      // estimates run about 5 % short of what the text really needs).
      if (twoH <= one) return _cue(body, twoH * 1.08 + 2 > c.maxHeight);
      return _cue(column(items), true);
    },
  );

  Widget _cue(Widget body, bool scrolls) => scrolls
      ? ScrollCue(
          builder: (context, controller) => SingleChildScrollView(
            controller: controller,
            padding: const EdgeInsets.only(bottom: 4),
            child: body,
          ),
        )
      : body;
}

/// One storage tile: the good's glyph and the ceiling this store gives it, and —
/// only where staff is posted — their share on a second line.
class _StorageTile extends StatelessWidget {
  final String emoji;
  final String label;
  final String total;
  final String? share;
  final bool dim;
  const _StorageTile({
    required this.emoji,
    required this.label,
    required this.total,
    required this.share,
    required this.dim,
  });

  static const double width = 84;
  static const double height = 26;
  static const double heightWith = 38;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Container(
      width: width,
      height: share == null ? height : heightWith,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: kBoxInk.withValues(alpha: 0.07),
        borderRadius: vr(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  total,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FoE.value(
                    size: 12,
                  ).copyWith(color: dim ? kBoxInkFaint : kBoxInk),
                ),
              ),
            ],
          ),
          if (share != null)
            Padding(
              padding: const EdgeInsets.only(left: 18),
              child: Text(
                share!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FoE.dim(size: 9.5).copyWith(color: kBoxInkSoft),
              ),
            ),
        ],
      ),
    ),
  );
}

/// The Crew card's body: every post's seats as tiles at the LARGEST scale at
/// which all of them fit the card ([_fitScale]) — a handful of monsters get big
/// tiles, 24 get small ones, and the card itself never changes size.
class _CrewGrid extends StatelessWidget {
  final List<_PostGroup> groups;
  const _CrewGrid({required this.groups});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final u = _fitScale(groups, c.maxWidth, c.maxHeight);
      final several = groups.length > 1;
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < groups.length; i++) ...[
              if (i > 0) const SizedBox(height: _kGroupGap),
              if (several)
                SizedBox(
                  height: _kGroupHeaderH,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          groups[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FoE.label(
                            size: 11,
                          ).copyWith(color: kBoxAccent),
                        ),
                      ),
                      Text(
                        '${groups[i].workers}/${groups[i].slots}',
                        style: FoE.value(size: 11).copyWith(color: kBoxInk),
                      ),
                    ],
                  ),
                ),
              if (groups[i].improves != null)
                SizedBox(
                  height: _kImprovesH,
                  child: Text(
                    groups[i].improves!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FoE.dim(size: 10).copyWith(color: kBoxInkSoft),
                  ),
                ),
              Wrap(
                spacing: _kSeatGap,
                runSpacing: _kSeatRowGap,
                children: [for (final t in groups[i].tiles) t(u)],
              ),
            ],
          ],
        ),
      );
    },
  );
}

const double _kSeatGap = 5;
const double _kSeatRowGap = 3;
const double _kGroupGap = 6;
const double _kGroupHeaderH = 18;
const double _kImprovesH = 13;

/// The tile scale range. 1.0 is the size the tiles were drawn at (60×88 with
/// the monster's head rising 16 out of the card); at 24 seats in the card's
/// ~390×175 the fit lands near 0.6.
const double _kMaxTileScale = 1.25;
const double _kMinTileScale = 0.5;

/// The height [groups] take at scale [u] in a body [w] wide — the same wrap
/// arithmetic the [Wrap] itself does (1/2 px of margin, so a rounding
/// difference can only make the real thing SHORTER than this).
double _crewHeight(List<_PostGroup> groups, double w, double u) {
  final tw = _kWorkerTileW * u;
  final th = (_kWorkerTileH + _kWorkerTileRise) * u;
  final cols = math.max(1, ((w - 0.5 + _kSeatGap) / (tw + _kSeatGap)).floor());
  var total = 0.0;
  for (var i = 0; i < groups.length; i++) {
    final n = groups[i].tiles.length;
    if (i > 0) total += _kGroupGap;
    if (groups.length > 1) total += _kGroupHeaderH;
    if (groups[i].improves != null) total += _kImprovesH;
    if (n == 0) continue;
    final rows = (n / cols).ceil();
    total += rows * th + (rows - 1) * _kSeatRowGap;
  }
  return total;
}

/// The largest tile scale at which every seat fits [w]×[h]; the floor if none
/// does (the grid then scrolls — past ~40 seats).
double _fitScale(List<_PostGroup> groups, double w, double h) {
  for (var u = _kMaxTileScale; u > _kMinTileScale; u -= 0.02) {
    if (_crewHeight(groups, w, u) <= h) return u;
  }
  return _kMinTileScale;
}

/// A recipe amount: "2", not "2.0".
String _num(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// One stationed monster: sprite + name left, ITS hourly contribution right.
/// Read-only — posting and un-posting both happen in the Edit sheet below
/// (user 2026-07-22, the ✕ per row is gone).
/// What one posted monster is doing here, worked out once — shown as a tile in
/// [_workerGrid].
typedef _WorkerReadout = ({
  /// Why it is not working, or null when it is.
  String? absence,

  /// The one-line figure (or the absence).
  String value,

  /// The stacked figures, for a post that feeds several systems or stores
  /// several goods; empty for every other.
  List<String> lines,
});

_WorkerReadout _workerReadout(
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
          ? '${buildPointsLabel(contrib)} 🔨'
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
  return (absence: absence, value: value, lines: lines);
}

/// The tiles' natural size at scale 1. [_CrewGrid] scales all three together
/// (see [_fitScale]); [_kWorkerTileRise] is the empty strip above the card the
/// monster's head rises into.
const double _kWorkerTileW = 60;
const double _kWorkerTileH = 72;
const double _kWorkerTileRise = 16;

/// A posted monster, as one of the build menu's cards (user 2026-09-18, "Variante
/// 3"): a light card with a hard tan shadow, the monster rising OUT of its top
/// edge with a cast shadow of its own, and its figure underneath. [u] scales
/// the whole tile; the name only shows while the tile is big enough to carry it
/// (long-press always gives name and details).
Widget _workerTile(
  CreatureInstance c,
  WorkshopRole role,
  int level,
  bool training,
  bool boost,
  List<String> storageKeys, {
  required double u,
  required VoidCallback? onTap,
}) {
  final r = _workerReadout(c, role, level, training, boost, storageKeys);
  final absent = r.absence != null;
  // The figure, or just the glyph of why it isn't working.
  final label = absent
      ? r.absence!.split(' ').first
      : (r.lines.isNotEmpty ? r.lines.first : r.value);
  final details = [
    training ? '${c.displayName} · Lv ${c.level}' : c.displayName,
    absent ? r.absence! : (r.lines.length > 1 ? r.lines.join('   ') : r.value),
  ].join('\n');
  final showName = u >= 0.9;
  return Tooltip(
    message: details,
    // A tap is the swap; the details wait for a long press.
    triggerMode: TooltipTriggerMode.longPress,
    child: Pressable(
      onTap: onTap,
      child: Opacity(
        opacity: absent ? 0.55 : 1,
        child: SizedBox(
          width: _kWorkerTileW * u,
          height: (_kWorkerTileH + _kWorkerTileRise) * u,
          child: CreatureSeatTile(
            face: CreatureFace.of(c),
            name: showName ? c.displayName : null,
            figure: label,
            u: u,
          ),
        ),
      ),
    ),
  );
}

/// A free seat: the same card at the same scale, dashed and empty, with an
/// amber "+".
Widget _emptyWorkerTile({
  required double u,
  required VoidCallback onTap,
  Key? anchorKey,
}) {
  final plus = (26 * u).clamp(16.0, 34.0);
  final tile = Semantics(
    label: 'Free seat — post a monster',
    button: true,
    child: Pressable(
      onTap: onTap,
      child: SizedBox(
        width: _kWorkerTileW * u,
        height: (_kWorkerTileH + _kWorkerTileRise) * u,
        child: Padding(
          padding: EdgeInsets.only(top: _kWorkerTileRise * u),
          child: CustomPaint(
            painter: DashedRRectPainter(
              color: CreamPalette.tan.withValues(alpha: 0.85),
              radius: 12 * u,
            ),
            child: Center(
              child: Container(
                width: plus,
                height: plus,
                decoration: BoxDecoration(
                  shape: BoxShape.rectangle,
                  color: CreamPalette.gold,
                  boxShadow: [
                    BoxShadow(
                      color: CreamPalette.goldDeep,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: PixelIcon(
                  Icons.add,
                  size: plus * 0.7,
                  color: CreamPalette.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return anchorKey == null ? tile : KeyedSubtree(key: anchorKey, child: tile);
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
      if (!canPay) {
        context.snack(
          'Not enough gold — you need 🪙 $cost, you have 🪙 ${ctrl.gold.toInt()}.',
          error: true,
        );
        return;
      }
      // The dialog's own context dies with the pop below — the root one
      // outlives it, so a refusal can still be shown.
      final root = Navigator.of(context, rootNavigator: true).context;
      Navigator.pop(context);
      final err = await ctrl.skipBuildWithGold(b);
      if (err != null && root.mounted) root.snack(err, error: true);
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
  final era = ctrl.dungeonMaxStage;
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
/// The level-up chips for the work posts and authored effects that change. Lines
/// of one group (a store's storage per good) collapse into ONE chip once there are
/// more than three — "Storage · each 1,050 → 1,600" when every good moves the same
/// way, "Storage · 12 values up" when they differ — so a store with twenty goods
/// does not drown the bar in twenty chips (user 2026-09-22).
List<String> _workChips(List<UpgradeLine> lines) {
  final byGroup = <String?, List<UpgradeLine>>{};
  for (final l in lines) {
    byGroup.putIfAbsent(l.group, () => []).add(l);
  }
  final out = <String>[];
  for (final e in byGroup.entries) {
    final group = e.key;
    final ls = e.value;
    String one(UpgradeLine l) =>
        '${group != null ? '$group · ' : ''}${l.label} '
        '${l.onlyNext ? l.next : '${l.now} → ${l.next}'}';
    if (group == null || ls.length <= 3) {
      out.addAll(ls.map(one));
      continue;
    }
    final first = ls.first;
    final same = ls.every((l) => l.now == first.now && l.next == first.next);
    out.add(
      same
          ? (first.onlyNext
                ? '$group · each ${first.next}'
                : '$group · each ${first.now} → ${first.next}')
          : '$group · ${ls.length} values up',
    );
  }
  return out;
}

/// The Upgrade bar — one line that never moves: "Lv 4 → Lv 5", what the level
/// buys as small chips (only what it actually MOVES — user 2026-07-26: "nur
/// anzeigen, wenn es effektiv auch etwas ändert"), the round button that opens
/// the max-level preview, and the Upgrade button with its cost inside (user
/// 2026-07-22 — the price is part of the offer, not a caption above it). See
/// building_definitions' level scaling for the curves behind the numbers.
Widget _upgradeBar(
  BuildContext context,
  SettlementController ctrl,
  PlacedBuilding b,
  BuildingDef def,
) {
  final atMax = b.level >= maxBuildingLevelFor(def, ctrl.dungeonMaxStage);
  final target = b.level + 1;
  final stock = ctrl.resources?.asMap ?? {};
  // Same slot check upgradeBuilding makes before it charges anything (user
  // 2026-09-22: "wenn ich nicht bauen kann, weil kein Bauarbeiter, queue
  // verfügbar ist, muss dies angezeigt werden. Auch bei upgrade") — shown up
  // front, like the cost, rather than only after a tap silently does nothing.
  final queueFull =
      ctrl.activeConstructionCount >= ctrl.maxBuildSlots &&
      ctrl.queuedConstructionCount >= ctrl.maxQueueSlots;
  final afford = !atMax && !queueFull && def.canAffordAt(target, stock);

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
      return buildPointsLabel(val);
    }
    return '${val.toStringAsFixed(1)}/h';
  }

  // What a level does to the WORK POSTS AND to every other authored effect — a
  // Builder Camp's "+1 build site at level 3" would otherwise be nowhere, and a
  // level whose entire point was that bonus would look like it bought nothing
  // (user 2026-07-26).
  final era = ctrl.dungeonMaxStage;
  final workLines = [
    ...workshopUpgradeLines(def, b.level, target),
    ...buildingEffectUpgradeLines(def, b.level, target, era),
  ];
  final movedKeys = [
    for (final k in outKeys)
      if ((now[k] ?? 0) != (next[k] ?? 0)) k,
  ];
  final movedWork = workLines.where((l) => l.changed).toList();
  final chips = <String>[
    for (final k in movedKeys)
      '${k == kHousingOutputKey ? 'Housing' : _resLabel(k)} '
          '${fmtOut(k, next[k])} ${k == kHousingOutputKey ? '🏠' : _resEmoji(k)}',
    ..._workChips(movedWork),
  ];

  Widget chip(String text) => Container(
    margin: const EdgeInsets.only(right: 6),
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [CreamPalette.tileTop, CreamPalette.tileBottom],
      ),
      borderRadius: vr(9),
      boxShadow: [
        BoxShadow(color: CreamPalette.tanShadow, offset: const Offset(0, 2)),
      ],
    ),
    child: Text(text, style: FoE.value(size: 11).copyWith(color: kBoxInk)),
  );

  return creamCard(
    padding: const EdgeInsets.fromLTRB(14, 0, 8, 0),
    child: SizedBox(
      height: _kBarH,
      child: Row(
        children: [
          Text(
            atMax ? 'Level ${b.level}' : 'Lv ${b.level} → Lv $target',
            style: FoE.title(size: 14).copyWith(color: kBoxInk),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: atMax
                ? Text(
                    'Maximum level reached.',
                    style: FoE.dim(size: 11).copyWith(color: kBoxInkSoft),
                  )
                : queueFull
                ? Text(
                    'Build queue is full (${ctrl.maxBuildSlots} active + '
                    '${ctrl.maxQueueSlots} queued) — free a slot first.',
                    style: FoE.dim(size: 11).copyWith(color: FoE.danger),
                  )
                // A level that moves nothing says so, rather than leaving a
                // bare button that reads as a rendering fault.
                : chips.isEmpty
                ? Text(
                    'This level changes no values — only the cost.',
                    style: FoE.dim(size: 11).copyWith(color: kBoxInkSoft),
                  )
                // Long lists (a store's every good) scroll sideways and SAY so
                // (user 2026-09-22: the level-up effects "werden nicht schön
                // dargestellt"): a fade and a ▸ tab until the end is reached.
                : ScrollCue(
                    axis: Axis.horizontal,
                    builder: (context, controller) => SingleChildScrollView(
                      controller: controller,
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [for (final t in chips) chip(t)]),
                    ),
                  ),
          ),
          const SizedBox(width: 6),
          // Small right-aligned peek at the effects at MAX level (user
          // 2026-07-24).
          _circleBtn(
            Icons.query_stats,
            () => showBuildingUpgradeSheet(context, def),
            size: 28,
          ),
          if (!atMax) ...[
            const SizedBox(width: 10),
            Pressable(
              onTap: afford ? () => _doUpgrade(context, ctrl, b.id) : null,
              // Only the resource(s) you are short of turn red, not the whole
              // line (user 2026-09-01); the button's own active/inactive
              // decoration is the tap cue.
              child: Container(
                width: 178,
                height: 40,
                alignment: Alignment.center,
                decoration: goldButton(active: afford),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Upgrade',
                      style: FoE.label(
                        size: 13,
                      ).copyWith(color: goldButtonInk(active: afford)),
                    ),
                    const SizedBox(height: 2),
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
        ],
      ),
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
  if (err == null) {
    Navigator.pop(context); // close dialog; the building is now rebuilding
  } else {
    context.snack(err, error: true);
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
  final ink = goldButtonInk(active: true);
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
  child: Pressable(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: goldButton(),
      alignment: Alignment.center,
      child: Text(
        label,
        style: FoE.label(size: 13).copyWith(color: goldButtonInk()),
      ),
    ),
  ),
);

// ── Worker assignment (creature economy) ──────────────────
// Each workshop role is staffed by SPECIFIC creatures; a role's output is
// the sum of its workers' civilian stat, so the player picks who works where.
// The seats themselves live in the Crew card ([_CrewGrid]) — what's left here
// are the notes about the crew as a whole.
Widget? _crewNotes(PlacedBuilding b, BuildingDef def, bool functional) {
  final ctrl = CreaturesController();
  final posted = ctrl.creatures.where((c) => c.assignedBuildingId == b.id);
  // Counts who's actually HERE — away creatures earn no XP either
  // (accruePassiveXp uses the same rule).
  final stationed = posted.where(ctrl.isWorkingNow).length;
  final away = posted.length - stationed;
  // Nothing to say = no line.
  if (!(stationed > 0 && !functional) && away <= 0) return null;
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (stationed > 0 && !functional)
        Text(
          'No road connection — nobody here is working, or earning XP.',
          style: FoE.dim(size: 11).copyWith(color: FoE.danger),
        ),
      if (away > 0)
        Text(
          '🎒 $away on expedition — post${away > 1 ? 's' : ''} held, '
          'no output until they return',
          style: FoE.dim(size: 10).copyWith(color: kBoxAccent),
        ),
    ],
  );
}

/// [swapId] opens the picker straight in swap mode for that monster.
void _openAssignPicker(
  BuildContext context,
  SettlementController ctrl,
  PlacedBuilding b,
  WorkshopRole role, {
  String? swapId,
}) => showAssignWorkers(
  context,
  ctrl: ctrl,
  building: b,
  role: role,
  swapId: swapId,
);

/// Training and the legendary slot keep their arrow: neither is a
/// stat→resource pair, and their left side alone would name nothing.
/// Shared between the Effects card's post headers and the assignment picker,
/// so the two cannot drift apart on what a post is called.
String _workRoleLabel(WorkshopRole role) => switch (role.resource) {
  WorkshopRole.kTraining => 'Training → XP',
  WorkshopRole.kLegendaryBoost =>
    '⭐ Legendary → ×${(1 + role.mult).toStringAsFixed(1)}',
  _ => role.stat.label,
};

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
    // Deliberately excluded from every real tick's progress right now (the
    // guided tutorial's Healing Hut step, user 2026-09-06: "Es soll gar kein
    // Timer laufen") — rate 0 here too, or this countdown extrapolates a
    // visibly moving number from buildRatePerHour regardless, same as if it
    // were actually building.
    if (e != null && !widget.ctrl.isConstructionFrozen(b.id)) {
      // buildRatePerHour already includes buildSpeedMultiplier — applying it
      // again here squared the bonus (25x under the jumpstart). Energy is a
      // continuous daily-steps rate now (user 2026-09-14), never a gate —
      // e.multiplier is exactly what GameEngine.tick's effectiveHours uses.
      //
      // NO /activeCount either: every site builds at the full rate (user
      // 2026-07-24), which is what tick() and the build menu both do. This
      // countdown was the last place still splitting, so a second site made
      // the first one's ETA silently double.
      rate = (widget.ctrl.buildRatePerHour / 3600.0) * e.multiplier;
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
        style: FoE.dim(size: 11).copyWith(color: kBoxAccent),
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
        RecessBar(value: pct / 100.0, color: kBoxAccent, height: 12),
        const SizedBox(height: 6),
        Text(
          _queued
              ? 'In build queue — waiting for a free slot'
              : widget.ctrl.isConstructionFrozen(widget.buildingId)
              ? '$pct% — only buildable with gold'
              // secondsLeft is only ever null for the instant before energy
              // has loaded — the rate itself never zeroes out any more
              // (user 2026-09-14), it just runs slower at low energy.
              : secondsLeft == null
              ? '$pct%'
              : '$pct%  ·  ${fmtDuration(secondsLeft)} remaining',
          // On the dialog's parchment recess — the warm accent reads, the app's
          // light gold does not.
          style: FoE.dim(size: 11).copyWith(color: kBoxAccent),
        ),
      ],
    );
  }
}
