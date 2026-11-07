import 'package:flutter/material.dart' hide Text;

import '../../../core/theme/cream_kit.dart';
import '../../creatures/models/creature_enums.dart';
import '../../creatures/models/species_balance.dart';
import '../../../core/theme/voxel_kit.dart' show vr;
import '../../../core/ui/game_text.dart';

/// BUDGETS & LIMITS, TO READ (user 2026-09-20: "das genau gleiche bei Budgets und
/// Grenzen" — shown with an explanation, changes by request).
///
/// The balance form is gone. This page lays out what the game currently runs on,
/// one card per subject: what the numbers are FOR in a sentence or two, then the
/// figures per rarity. To change one, say which and to what.
class DevBudgetsView extends StatelessWidget {
  const DevBudgetsView({super.key});

  static String _n(double v) {
    if (!v.isFinite) return '–';
    final r = (v * 100).round() / 100;
    return r == r.roundToDouble() ? r.round().toString() : r.toString();
  }

  static String _hours(double h) =>
      h >= 24 && h % 24 == 0 ? '${_n(h)} h (${_n(h / 24)} d)' : '${_n(h)} h';

  @override
  Widget build(BuildContext context) {
    final b = kSpeciesBalance;
    final xp = kXpBalance;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _card(
            'Stat-Budget je Seltenheit',
            Icons.balance,
            'Jede Art bekommt so viele Punkte, wie ihre Seltenheit erlaubt, '
                'verteilt auf Kampf- und Arbeitswerte. «Basis» ist der Wert auf '
                'Stufe 1, «Wachstum» kommt je Level dazu. Das Limit deckelt ein '
                'einzelnes Attribut, damit das Budget eine Form hat und nicht '
                'nur eine Summe (0 = kein Deckel). Eine Art, deren Summe nicht '
                'stimmt, steht in der Liste mit einem roten Punkt.',
            _table(
              ['Kampf Basis', 'Arbeit Basis', 'Kampf +/Lv', 'Arbeit +/Lv'],
              (r) => [
                _n(b.of(r).combatBase),
                _n(b.of(r).workBase),
                _n(b.of(r).combatGrowth),
                _n(b.of(r).workGrowth),
              ],
            ),
            extra: _table(
              [
                'Limit K-Basis',
                'Limit A-Basis',
                'Limit K-Wachstum',
                'Limit A-Wachstum',
              ],
              (r) => [
                _n(b.of(r).combatMaxBase),
                _n(b.of(r).workMaxBase),
                _n(b.of(r).combatMaxGrowth),
                _n(b.of(r).workMaxGrowth),
              ],
            ),
          ),
          _card(
            'Fang',
            Icons.catching_pokemon,
            '«Fangrate» ist die Grundchance, «Treffer» sagt, wie oft der Ring '
                'nacheinander im goldenen Band landen muss (ein Fehler, und das '
                'Monster entkommt). «Gewicht» bestimmt, wie oft die Seltenheit '
                'auf einer Jagd auftaucht — relativ zu den anderen.',
            _table(
              ['Fangrate', 'Treffer', 'Gewicht'],
              (r) => [
                _n(b.of(r).catchRate),
                '${b.of(r).catchHits}',
                _n(b.of(r).encounterWeightBase),
              ],
            ),
          ),
          _card(
            'Zucht',
            Icons.egg_alt,
            'Zwei Uhren: die Paarung in der Zuchthütte und das Schlüpfen im '
                'Brutkasten. Die Stunden sind die Grundzeit je Seltenheit; die '
                'Züchter, die im Gebäude stehen, kürzen sie. Jede Paarung kostet '
                'ausserdem Waren aus der Epoche der Eltern. Legendäre werden nie '
                'gezüchtet — ihre Werte sind ohne Wirkung.',
            _table(
              ['Paarung', 'Schlüpfen', 'Waren je Paarung'],
              (r) => [
                _hours(b.of(r).breedHours),
                _hours(b.of(r).hatchHours),
                _n(b.of(r).breedGoods),
              ],
            ),
          ),
          _card(
            'Heilung',
            Icons.healing,
            'Heilen kostet Zeit und Waren, beides je fehlendem Lebenspunkt. '
                'Seltenere Monster liegen länger auf dem Tisch und kosten mehr. '
                'Ein K.O. verdoppelt beides (das ist eine globale Zahl); das '
                'Gebäude und der Heiler in ihm kürzen es weiter.',
            _table(
              ['Sekunden je HP', 'Waren je HP'],
              (r) => [_n(b.of(r).healSecondsPerHp), _n(b.of(r).healGoodsPerHp)],
            ),
          ),
          _xpCard(xp),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: CreamPalette.tan.withValues(alpha: 0.14),
              borderRadius: vr(10),
            ),
            child: Text(
              'Zum Ändern: sag mir, welche Zahl und auf welchen Wert — ich '
              'passe sie an.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: kBoxInkSoft,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ── XP ────────────────────────────────────────────────────

  Widget _xpCard(XpConfig xp) {
    Widget row(String label, String value, String help) => Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: kBoxInk,
              ),
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: kBoxAccent,
              ),
            ),
          ),
          Expanded(
            child: Text(
              help,
              style: TextStyle(fontSize: 11, height: 1.35, color: kBoxInkSoft),
            ),
          ),
        ],
      ),
    );
    return _card(
      'Erfahrung',
      Icons.star_rounded,
      'Wie schnell Monster Level machen: die Kurve, was besiegte Gegner '
          'wert sind und was Training und Arbeit nebenbei einbringen. Kämpfen '
          'und Trainieren sind der Hauptweg, Arbeit ist nur ein Rinnsal.',
      Column(
        children: [
          row(
            'Kurve: Faktor × Level^Exponent',
            '${_n(xp.curveFactor)} × L^${_n(xp.curveExponent)}',
            'EP von Level L auf L+1. Beispiel: Lv 1 → ${xp.xpToNext(1)}, '
                'Lv 10 → ${xp.xpToNext(10)}, Lv 20 → ${xp.xpToNext(20)}.',
          ),
          row(
            'Training',
            '${_n(xp.trainingPerHour)}/h',
            'EP je Stunde im Trainingsplatz. Der Trainierende arbeitet '
                'nicht, das kostet also Ertrag.',
          ),
          row(
            'Arbeit',
            '${_n(xp.workPerHour)}/h',
            'EP je Stunde auf einem Posten — in jedem Gebäude gleich, '
                '×${_n(xp.workLevelGrowth)} je Gebäudelevel.',
          ),
          row(
            'Besiegter Gegner',
            '${_n(xp.killFactor)} × L^${_n(xp.killExponent)}',
            'EP, die ein Gegner der Stufe L wert ist (Summe des Gegnerteams, '
                'dann auf das Team verteilt). Beispiel: Lv 10 → '
                '${xp.killXp(10).round()}, Lv 30 → ${xp.killXp(30).round()}.',
          ),
          row(
            'Boss',
            '×${_n(xp.bossMultiplier)}',
            'Ein Boss zählt so viele normale Gegner.',
          ),
        ],
      ),
    );
  }

  // ── Parts ─────────────────────────────────────────────────

  Widget _card(
    String title,
    IconData icon,
    String explanation,
    Widget body, {
    Widget? extra,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: sectionCard(
      title: title,
      icon: icon,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            explanation,
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              fontWeight: FontWeight.w400,
              color: kBoxInkSoft,
            ),
          ),
          const SizedBox(height: 10),
          body,
          if (extra != null) ...[const SizedBox(height: 8), extra],
        ],
      ),
    ),
  );

  /// A rarity × figures grid: the rarity in its own colour, then one column
  /// per header.
  static Widget _table(
    List<String> headers,
    List<String> Function(CreatureRarity r) cells,
  ) {
    Widget cell(
      String t, {
      bool head = false,
      Color? color,
      bool first = false,
    }) => Expanded(
      flex: first ? 3 : 4,
      child: Text(
        t,
        textAlign: first ? TextAlign.left : TextAlign.right,
        style: TextStyle(
          fontSize: head ? 10 : 12,
          fontWeight: head ? FontWeight.w400 : FontWeight.w400,
          letterSpacing: head ? 0.6 : 0,
          color: color ?? (head ? kBoxAccent : kBoxInk),
        ),
      ),
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(
            children: [
              cell('', first: true),
              for (final h in headers) cell(h.toUpperCase(), head: true),
            ],
          ),
        ),
        for (final r in CreatureRarity.values)
          Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: r.index.isEven
                  ? CreamPalette.tan.withValues(alpha: 0.10)
                  : null,
              borderRadius: vr(7),
            ),
            child: Row(
              children: [
                cell(r.label, color: r.color, first: true),
                for (final v in cells(r)) cell(v),
              ],
            ),
          ),
      ],
    );
  }
}
