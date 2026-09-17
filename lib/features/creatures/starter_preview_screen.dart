import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import 'creature_detail_screen.dart';
import 'models/creature_enums.dart';
import 'models/creature_instance.dart';
import 'models/species_def.dart';
import 'services/creatures_controller.dart';

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
      // No pop-up any more (user 2026-08-29: "wirklich alle pop up
      // nachrichten... löschen") — the button re-enabling (_adopting back to
      // false) is the signal to try again.
      setState(() => _adopting = false);
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => CreatureDetailScreen(creatureId: created.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => CreatureDetailScreen(
    previewCreature: _draft,
    footer: _confirmButton(),
  );

  Widget _confirmButton() => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: _adopting ? null : _confirm,
      borderRadius: BorderRadius.circular(FoE.radiusSmall),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: FoE.tapTarget),
        alignment: Alignment.center,
        // The starter's OWN element colour (user 2026-09-05: "den choose
        // button in der Farbe des Typs"), not the app's generic accent —
        // this button is the one place on the screen that's already
        // committing to a specific starter, so it wears that starter's
        // colour rather than a neutral one.
        decoration: BoxDecoration(
          color: widget.species.element.color,
          borderRadius: BorderRadius.circular(FoE.radiusSmall),
        ),
        child: Text(
          _adopting ? 'Choosing…' : 'Choose ${_draft.displayName}',
          textAlign: TextAlign.center,
          style: FoE.title(size: 13).copyWith(color: FoE.bg),
        ),
      ),
    ),
  );
}
