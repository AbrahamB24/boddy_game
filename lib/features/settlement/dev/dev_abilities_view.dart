import 'package:flutter/material.dart' hide Text;

import '../../../core/theme/cream_kit.dart';
import '../../creatures/models/ability_def.dart';
import '../../creatures/models/creature_enums.dart';
import '../../creatures/models/species_def.dart';
import 'dev_lists.dart';
import '../../../core/theme/voxel_kit.dart' show vr;
import '../../../core/ui/game_text.dart';

/// THE ABILITIES, TO READ (user 2026-09-20: "Abilities anzeigen lassen mit
/// Erklärung — und ich gebe dir den Auftrag, falls etwas geändert werden muss").
///
/// The ability editor is gone. What is left is the list and, for the picked
/// ability, the plain-words version of everything its numbers mean: what it does,
/// what it costs and why, who learns it. A change is a request, not a form.
class DevAbilitiesView extends StatefulWidget {
  const DevAbilitiesView({super.key});

  @override
  State<DevAbilitiesView> createState() => _DevAbilitiesViewState();
}

class _DevAbilitiesViewState extends State<DevAbilitiesView> {
  String _search = '';
  String? _selected;

  List<AbilityDef> _visible() {
    final q = _search.trim().toLowerCase();
    return [
      for (final a in kAbilityDefs.values)
        if (q.isEmpty ||
            a.name.toLowerCase().contains(q) ||
            a.id.toLowerCase().contains(q))
          a,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  @override
  Widget build(BuildContext context) {
    final list = _visible();
    final picked =
        kAbilityDefs[_selected] ?? (list.isEmpty ? null : list.first);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 292,
          child: creamCard(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DevSearch(onChanged: (v) => setState(() => _search = v)),
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 5),
                  child: Text(
                    '${list.length} / ${kAbilityDefs.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: kBoxAccent,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 4),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 5),
                    itemBuilder: (_, i) {
                      final a = list[i];
                      return devRow(
                        leading: Text(
                          a.element.emoji,
                          style: const TextStyle(fontSize: 17),
                        ),
                        title: a.name,
                        note: '${a.resolvedApCost} AP',
                        selected: identical(a, picked),
                        onTap: () => setState(() => _selected = a.id),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: creamCard(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: picked == null
                ? Center(
                    child: Text(
                      'Keine Abilities.',
                      style: TextStyle(color: kBoxInkSoft),
                    ),
                  )
                : _Explanation(a: picked),
          ),
        ),
      ],
    );
  }
}

/// One ability in words.
class _Explanation extends StatelessWidget {
  final AbilityDef a;
  const _Explanation({required this.a});

  /// Species that learn [a], with the stage they get it at.
  List<String> _learnedBy() => [
    for (final s in kSpeciesDefs.values)
      for (final sa in s.abilities)
        if (sa.abilityId == a.id) '${s.name} (Stufe ${sa.unlockStage + 1})',
  ]..sort();

  String get _kindLine => switch (a.kind) {
    AbilityKind.damage =>
      'Schaden: Angriff gegen Verteidigung — es gibt keine Trennung in '
          'körperlich und magisch. Nur eine Ability mit Typ kann Bonusschaden '
          'landen; der normale Angriff ist typlos.',
    AbilityKind.heal =>
      'Heilung: gibt Leben zurück und richtet keinen Schaden an.',
    AbilityKind.buff => 'Selbst-Buff: wirkt nur auf den, der sie einsetzt.',
  };

  String get _costLine {
    if (a.apCost > 0) {
      return '${a.resolvedApCost} AP — von Hand festgelegt, die Formel wird '
          'übergangen.';
    }
    final power = a.totalPower.toStringAsFixed(0);
    return '${a.resolvedApCost} AP — aus der Gesamtpower $power gerechnet '
        '(Power + Wert jedes Effekts + Priorität, geteilt durch $kPowerPerAp, '
        'mindestens ${a.kind == AbilityKind.buff ? kBuffApCost : kMinAbilityApCost}, '
        'höchstens $kMaxActionPoints).';
  }

  @override
  Widget build(BuildContext context) {
    final learners = _learnedBy();
    final effects = [for (final e in a.effects) ...describeAbilityEffect(e)];
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(a.element.emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  a.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w400,
                    color: kBoxInk,
                  ),
                ),
              ),
              _chip('${a.resolvedApCost} AP', gold: true),
              const SizedBox(width: 6),
              _chip(a.kind.label),
            ],
          ),
          const SizedBox(height: 2),
          Text(a.id, style: TextStyle(fontSize: 11, color: kBoxInkFaint)),
          if (a.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              a.description,
              style: TextStyle(fontSize: 13, height: 1.45, color: kBoxInkSoft),
            ),
          ],
          _section('Was sie tut'),
          _text(_kindLine),
          _text('Ziel: ${a.target.label}.'),
          if (a.kind == AbilityKind.damage)
            _text(
              'Power ${a.power}. Der Typ ${a.element.emoji} ${a.element.label} '
              'gibt den Bonus des Angreifers (STAB) und den Typ-Vorteil oder '
              '-Nachteil gegen das Ziel.',
            )
          else
            _text('Typ: ${a.element.emoji} ${a.element.label}.'),
          if (a.extraHitChance > 0)
            _text(
              a.extraHitSameTarget
                  ? 'Kann dasselbe Ziel noch einmal treffen: zweiter Treffer '
                        'mit ${(a.extraHitChance * 100).round()} %, dritter mit '
                        '${(a.extraHitChance * a.extraHitChance * 100).round()} %.'
                  : 'Kann noch einen ANDEREN Gegner treffen: zweiter Treffer '
                        'mit ${(a.extraHitChance * 100).round()} %, dritter mit '
                        '${(a.extraHitChance * a.extraHitChance * 100).round()} %.',
            ),
          if (a.priority > 0)
            _text(
              'Priorität +${a.priority}: der nächste Zug des Anwenders rückt '
              'etwas nach vorn.',
            ),
          if (effects.isNotEmpty) ...[
            _section('Effekte'),
            for (final line in effects) _bullet(line),
          ],
          _section('Preis'),
          _text(_costLine),
          if (a.isOverPricedOut)
            _text(
              'Achtung: stärker, als der grösste AP-Vorrat bezahlen kann — '
              'jede Power über $kMaxPricedPower ist gratis.',
              warn: true,
            ),
          _section('Wer sie lernt'),
          _text(learners.isEmpty ? 'Keine Art.' : learners.join(', ')),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: CreamPalette.tan.withValues(alpha: 0.14),
              borderRadius: vr(10),
            ),
            child: Text(
              'Zum Ändern: sag mir, welche Ability und was — ich passe sie an.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: kBoxInkSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String t, {bool gold = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: gold ? CreamPalette.gold : CreamPalette.tan.withValues(alpha: 0.2),
      borderRadius: vr(9),
    ),
    child: Text(
      t,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: kBoxInk,
      ),
    ),
  );

  Widget _section(String t) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 4),
    child: Row(
      children: [
        Text(
          t.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            letterSpacing: 1.1,
            color: kBoxAccent,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 1,
            color: CreamPalette.tan.withValues(alpha: 0.55),
          ),
        ),
      ],
    ),
  );

  Widget _text(String t, {bool warn = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      t,
      style: TextStyle(
        fontSize: 13,
        height: 1.45,
        fontWeight: FontWeight.w400,
        color: warn ? CreamPalette.warn : kBoxInkSoft,
      ),
    ),
  );

  Widget _bullet(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('•  ', style: TextStyle(color: kBoxAccent)),
        Expanded(
          child: Text(
            t,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w400,
              color: kBoxInkSoft,
            ),
          ),
        ),
      ],
    ),
  );
}
