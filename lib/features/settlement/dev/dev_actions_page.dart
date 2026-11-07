import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart' show FilteringTextInputFormatter;

import '../../../core/theme/cream_kit.dart';
import '../../../core/ui/pressable.dart';
import '../../creatures/models/breeding_job.dart';
import '../../creatures/models/creature_instance.dart';
import '../../creatures/services/breeding_controller.dart';
import '../../creatures/services/creatures_controller.dart';
import '../../creatures/services/expedition_controller.dart';
import '../data/building_definitions.dart'
    show kDevResetFloat, kEnergyMaxPercent;
import '../settlement_controller.dart';
import 'dev_species_tools.dart';
import '../../../core/theme/voxel_kit.dart' show vr;
import '../../../core/theme/voxel_icons.dart';
import '../../../core/ui/game_text.dart';

/// THE DEV MENU'S ACTIONS PAGE (user 2026-09-20: "alle dev buttons wie heal all
/// oder add resources etc. im Devmenü verstecken … ich will alle Menüs so sehen
/// wie die Spieler").
///
/// Every cheat that used to sit inside a player's screen — Heal all on the
/// Monsters hub, the resource grant and reset on the settlement, "+500 XP" and
/// "Evolve" on a monster, "Finish now" on trips, breeding and hatching, "Add
/// steps" in the Energy sheet — lives here now, so the player-facing menus are
/// the players'. Plus the intro restart and the two bulk species tools that were
/// in the Dev menu's toolbar.
class DevActionsPage extends StatefulWidget {
  const DevActionsPage({super.key});

  @override
  State<DevActionsPage> createState() => _DevActionsPageState();
}

class _DevActionsPageState extends State<DevActionsPage> {
  final _settlement = SettlementController();
  final _creatures = CreaturesController();
  final _steps = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _steps.dispose();
    super.dispose();
  }

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// Runs [job] with the page's busy flag up, then says [done].
  Future<void> _run(Future<void> Function() job, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
      _say(done);
    } catch (e) {
      _say('Fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addSteps() async {
    final n = int.tryParse(_steps.text) ?? 0;
    if (n <= 0) return;
    await _run(() => _settlement.addSteps(n), '👣 $n Schritte hinzugefügt');
    _steps.clear();
  }

  Future<void> _finishTrips() async {
    final ctrl = ExpeditionController();
    final running = ctrl.travelling();
    await _run(() async {
      for (final e in running) {
        await ctrl.devFinishNow(e);
      }
    }, '⏩ ${running.length} Ausflüge beendet');
  }

  Future<void> _finishBreeding() async {
    final ctrl = BreedingController();
    final running = [
      for (final j in ctrl.jobs)
        if (j.status != BreedingStatus.egg && !j.isReady) j,
    ];
    await _run(() async {
      for (final j in running) {
        await ctrl.devFinishNow(j);
      }
    }, '⏩ ${running.length} Zucht- und Brutvorgänge beendet');
  }

  Future<void> _restartIntro() async {
    await _settlement.restartIntro();
    if (!mounted) return;
    Navigator.of(context).maybePop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Intro restarted — jumpstart is back on.')),
    );
  }

  Future<void> _reroll() async {
    await rerollAllStats(context);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final cols = box.maxWidth >= 720 ? 2 : 1;
      final left = _column([_stateCard(), _waitCard()]);
      final right = _column([_monsterCard(), _speciesCard()]);
      return cols == 2
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: left),
                const SizedBox(width: 8),
                Expanded(child: right),
              ],
            )
          : ListView(children: [left, right]);
    },
  );

  Widget _column(List<Widget> cards) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in cards) ...[c, const SizedBox(height: 8)],
      ],
    ),
  );

  // ── Cards ─────────────────────────────────────────────────

  Widget _stateCard() => sectionCard(
    title: 'Spielstand',
    icon: Icons.tune,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _action(
          '🪙 Gold, Holz und Stein auffüllen',
          'Je ${kDevResetFloat.round()} — nur damit ein Gebäude unter Test nicht auf einen Ausflug wartet.',
          () => _run(
            () => _settlement.grantResources({
              'gold': kDevResetFloat,
              'wood': kDevResetFloat,
              'stone': kDevResetFloat,
            }),
            '🪙 Vorräte aufgefüllt',
          ),
        ),
        _action(
          '🩹 Alle Monster heilen',
          'Gratis und sofort — ohne Waren und ohne Wartezeit der Heilerhütte.',
          () => _run(
            () => _creatures.healAll(free: true).then((_) {}),
            '🩹 Alle Monster geheilt',
          ),
        ),
        _action(
          '🧬 Jedes Monster, jede Stufe',
          'Eines von jeder Art und jeder Evolutionsstufe, die du noch nicht hast — '
              'ohne Rücksicht auf die Unterkünfte. Zum Anschauen.',
          () => _run(() async {
            final n = await _creatures.devGrantAllSpeciesAndStages();
            _say('🧬 $n Monster hinzugefügt');
          }, '🧬 Fertig'),
        ),
        _action(
          '⚡ Energie auffüllen',
          'Der Pool springt sofort auf ${kEnergyMaxPercent.round()} %.',
          () => _run(() => _settlement.devFillEnergy(), '⚡ Energie aufgefüllt'),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.5),
                  borderRadius: vr(10),
                  border: Border.all(
                    color: CreamPalette.tan.withValues(alpha: 0.55),
                    width: 1.5,
                  ),
                ),
                child: TextField(
                  controller: _steps,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  cursorColor: kBoxInk,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: kBoxInk,
                  ),
                  decoration: InputDecoration.collapsed(
                    hintText: '👣 Schritte, z. B. 5000',
                    hintStyle: TextStyle(fontSize: 12, color: kBoxInkFaint),
                  ),
                  onSubmitted: (_) => _addSteps(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _pill('Hinzufügen', _addSteps, gold: true),
          ],
        ),
        const SizedBox(height: 10),
        _action(
          '↺ Intro neu starten',
          'Der Vorsprung (schnellere Ausflüge, Bauzeiten, schwächere Gegner) ist wieder an.',
          _restartIntro,
        ),
      ],
    ),
  );

  Widget _waitCard() => sectionCard(
    title: 'Wartezeiten überspringen',
    icon: Icons.fast_forward,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _action(
          '⏩ Alle laufenden Ausflüge beenden',
          'Sie kommen sofort heim und lösen sich auf.',
          _finishTrips,
        ),
        _action(
          '⏩ Zucht und Brut beenden',
          'Paarungen legen ihr Ei, Eier im Brutkasten schlüpfen.',
          _finishBreeding,
        ),
      ],
    ),
  );

  Widget _monsterCard() => sectionCard(
    title: 'Monster',
    icon: Icons.pets,
    child: AnimatedBuilder(
      animation: _creatures,
      builder: (context, _) {
        final list = _creatures.creatures;
        if (list.isEmpty) {
          return Text(
            'Du hast noch kein Monster.',
            style: TextStyle(fontSize: 12, color: kBoxInkSoft),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final c in list) _monsterRow(c)],
        );
      },
    ),
  );

  Widget _monsterRow(CreatureInstance c) {
    final next = c.hasNextStage
        ? c.species?.stageAt(c.stage + 1).name ?? 'next'
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
        decoration: raisedTile(radius: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${c.displayName} · Lv ${c.level}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: kBoxInk,
                ),
              ),
            ),
            _pill(
              '+500 XP',
              () => _run(
                () => _creatures.devGainXp(c, 500),
                '🛠 ${c.displayName} +500 XP',
              ),
            ),
            if (next != null) ...[
              const SizedBox(width: 6),
              _pill(
                'Evolve → $next',
                () => _run(() async {
                  final err = await _creatures.devEvolve(c);
                  if (err != null) throw err;
                }, '🛠 ${c.displayName} hat sich entwickelt'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _speciesCard() => sectionCard(
    title: 'Arten',
    icon: Icons.balance,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _action(
          '⚖️ Rote Budgets reparieren',
          'Bringt jede Art ausser Budget auf ihr Gesamtbudget; Verteilung und Evolutionsschübe bleiben.',
          () => normalizeSpeciesBudgets(context),
        ),
        _action(
          '🎲 Alle Stats neu würfeln',
          'Überschreibt die Stat-Kurven ALLER Arten (Rolle, Prioritäten, Reife). Nicht rückgängig zu machen.',
          _reroll,
          warn: true,
        ),
      ],
    ),
  );

  // ── Parts ─────────────────────────────────────────────────

  /// A whole-row action: a title, a line of what it does, a button on the right.
  Widget _action(
    String title,
    String help,
    VoidCallback onTap, {
    bool warn = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Pressable(
      onTap: _busy ? null : onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
        decoration: raisedTile(radius: 11, locked: _busy),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: warn ? CreamPalette.warn : kBoxInk,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    help,
                    style: TextStyle(fontSize: 11, color: kBoxInkSoft),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            PixelIcon(Icons.play_arrow_rounded, color: kBoxInkFaint, size: 20),
          ],
        ),
      ),
    ),
  );

  Widget _pill(String label, VoidCallback onTap, {bool gold = false}) =>
      Pressable(
        onTap: _busy ? null : onTap,
        child: Container(
          height: gold ? 36 : 28,
          padding: EdgeInsets.symmetric(horizontal: gold ? 16 : 10),
          alignment: Alignment.center,
          decoration: gold ? goldButton() : raisedTile(radius: 9),
          child: Text(
            label,
            style: TextStyle(
              fontSize: gold ? 12 : 11,
              fontWeight: FontWeight.w400,
              color: gold ? goldButtonInk() : kBoxInk,
            ),
          ),
        ),
      );
}
