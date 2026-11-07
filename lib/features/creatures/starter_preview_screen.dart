import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;

import '../../core/theme/cream_kit.dart' show CreamPalette;
import '../../core/theme/foe_theme.dart';
import '../../core/ui/feel.dart';
import '../../core/ui/snack.dart';
import 'creature_detail_screen.dart';
import 'models/creature_enums.dart';
import 'models/creature_instance.dart';
import 'models/species_def.dart';
import 'services/creatures_controller.dart';
import '../../core/theme/voxel_kit.dart' show vr;
import '../../core/ui/game_text.dart';

/// A look at a starter species BEFORE anything is adopted — pushed from
/// [CollectionScreen]'s starter picker in place of the old confirm dialog.
///
/// Rolls its [_draft] once (gender + Gaussian genes) and renders it through
/// the real [CreatureDetailScreen] — the same Pokédex screen every owned
/// creature gets (user 2026-09-02: "Dieser Screen bei choose your starter
/// soll 1:1 so aussehen wie der Monsterdetailscreen"), with its Release/dev
/// footer swapped for a single "Choose" button. Nothing is created until
/// [_confirm] runs: the draft stays a plain, unsaved [CreatureInstance] (no
/// id, not in [CreaturesController]'s list) while this screen is up, so the
/// system back button just pops with no trace to undo. Confirming persists
/// this EXACT draft (see [CreaturesController.adoptStarter]) and replaces
/// this screen with the newly adopted creature's own detail screen (user
/// 2026-08-24: "will ich in den monster Detail screen von diesem Monster
/// kommen ... Gehe ich zurück, komme ich wieder in den choose your starter
/// screen") — the replace (not a push) is what makes that back button land
/// on the starter picker rather than back on this preview.
class StarterPreviewScreen extends StatefulWidget {
  final SpeciesDef species;

  const StarterPreviewScreen({super.key, required this.species});

  @override
  State<StarterPreviewScreen> createState() => _StarterPreviewScreenState();
}

class _StarterPreviewScreenState extends State<StarterPreviewScreen> {
  final _ctrl = CreaturesController();
  bool _adopting = false;
  late final CreatureInstance _draft;

  @override
  void initState() {
    super.initState();
    final rng = math.Random();
    final species = widget.species;
    _draft = CreatureInstance(
      id: '',
      userId: '',
      speciesId: species.id,
      gender: rng.nextBool() ? CreatureGender.male : CreatureGender.female,
      level: 1,
      statBase: CreatureInstance.rollBaseGenes(species, rng),
      statSlope: CreatureInstance.rollSlopeGenes(species, rng),
      isStarter: true,
      // This preview IS the real detail screen (user 2026-09-02), abilities
      // included — backfill here so what's shown before adopting matches
      // what CreaturesController.adoptStarter grants once it is.
      learnedAbilityIds: null,
    )..backfillAbilities();
  }

  Future<void> _confirm() async {
    setState(() => _adopting = true);
    final created = await _ctrl.adoptStarter(_draft);
    if (!mounted) return;
    if (created == null) {
      setState(() => _adopting = false);
      context.snack(
        'Could not adopt it — check your connection and try again.',
        error: true,
      );
      return;
    }
    // Every other "you got a monster" moment plays this (catching one in
    // battle, hatching an egg — see FeelEvent.fanfare's own doc: "earned
    // something bigger"). The very first one of all had none at all (2026-09-30
    // QA pass) — the single biggest moment in a new player's first minute
    // landed completely silent.
    Feel.fanfare();
    // Straight back to Home, not the new creature's detail screen (user
    // 2026-09-30, reversing the 2026-08-24 decision this used to follow):
    // the tutorial's next step lives on Home, and landing on a detail
    // screen first just adds a detour before the guide card can show.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) =>
      CreatureDetailScreen(previewCreature: _draft, footer: _confirmButton());

  Widget _confirmButton() {
    // The starter's OWN element colour (user 2026-09-05: "den choose button
    // in der Farbe des Typs"), not the app's generic accent — but NOT a flat
    // fill of it any more (user screenshot 2026-09-30: "choose Button fast
    // nicht sichtbar"): CreatureDetailScreen washes the WHOLE page in that
    // same element colour, so a flat match painted the button straight into
    // its own background. A gradient down to a darker shade of the same hue
    // keeps "wears the starter's colour" while actually reading as a raised
    // button against the flat wash behind it — value contrast, not a
    // different colour.
    final base = widget.species.element.color;
    final deep = Color.lerp(base, Colors.black, 0.4)!;
    final light = deep.computeLuminance() > 0.35;
    final ink = light ? CreamPalette.ink : Colors.white;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _adopting ? null : _confirm,
        borderRadius: vr(FoE.radiusSmall),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: FoE.tapTarget),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [base, deep],
            ),
            borderRadius: vr(FoE.radiusSmall),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.4),
              width: 1.5,
            ),
            boxShadow: const [
              BoxShadow(color: Color(0x59000000), offset: Offset(0, 3)),
            ],
          ),
          child: Text(
            _adopting ? 'Choosing…' : 'Choose ${_draft.displayName}',
            textAlign: TextAlign.center,
            style: FoE.title(size: 13).copyWith(
              color: ink,
              shadows: light
                  ? null
                  : const [
                      Shadow(
                        color: Color(0xAA000000),
                        offset: Offset(0, 1),
                      ),
                    ],
            ),
          ),
        ),
      ),
    );
  }
}
