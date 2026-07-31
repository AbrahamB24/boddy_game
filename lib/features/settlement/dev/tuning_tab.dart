import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;

import '../../../core/theme/foe_theme.dart';
import '../../../core/tuning/game_tuning.dart';

// ── One menu for a whole group of dials (user 2026-07-29) ──────────────────
// "mir ist wichtig, dass es so einfach und übersichtlich wie nur möglich ist."
//
// So: ONE widget for all three menus, and one shape for every row — name, one
// line on what it does, the number, and a live line saying what that number
// MEANS in play. No dialogs, no nesting, no per-dial screens. What differs
// between Settlement, Kampagne and Monster is only which dials the registry
// hands over — see kDials.
//
// The "what it means" line is the point of the whole thing: a build-time
// constant of 100 says nothing, "−50 % bei 100 · −80 % bei 400" is a decision
// you can make. It recomputes as you type.
class TuningTab extends StatefulWidget {
  final TuningGroup group;
  const TuningTab({super.key, required this.group});

  @override
  State<TuningTab> createState() => _TuningTabState();
}

class _TuningTabState extends State<TuningTab> {
  final Map<String, TextEditingController> _ctrls = {};
  bool _dirty = false;
  bool _saving = false;

  List<Dial> get _dials =>
      [for (final d in kDials) if (d.group == widget.group) d];

  @override
  void initState() {
    super.initState();
    for (final d in _dials) {
      _ctrls[d.id] = TextEditingController(text: _fieldText(d));
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _fieldText(Dial d) => _fmt(d.toField(GameTuning.i.raw(d.id)));

  static String _fmt(double v) {
    if (!v.isFinite) return '0';
    // Four decimals is enough for a 6.25 % crit chance and keeps 0.5 from
    // rendering as 0.5000.
    final r = (v * 10000).round() / 10000;
    return r == r.roundToDouble() ? r.round().toString() : r.toString();
  }

  void _onTyped(Dial d, String raw) {
    final shown = double.tryParse(raw.replaceAll(',', '.'));
    if (shown == null) return; // half-typed ("-", "0.") keeps the last value
    var v = d.fromField(shown);
    if (d.min != null && v < d.min!) v = d.min!;
    GameTuning.i.set(d.id, v);
    if (!_dirty) setState(() => _dirty = true);
  }

  void _resetDial(Dial d) {
    GameTuning.i.reset(d.id);
    _ctrls[d.id]!.text = _fieldText(d);
    setState(() => _dirty = true);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final err = await GameTuning.i.save(widget.group);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _dirty = err != null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(err ?? 'Gespeichert — gilt ab sofort für alle.'),
        backgroundColor: err == null ? FoE.positive : FoE.danger,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds on every keystroke so the "what it means" lines follow along —
    // including the ones that read a NEIGHBOURING dial (max level = eras ×
    // levels), which is exactly why they can't be computed once in initState.
    return AnimatedBuilder(
      animation: GameTuning.i,
      builder: (context, _) {
        final dials = _dials;
        final sections = <String, List<Dial>>{};
        for (final d in dials) {
          sections.putIfAbsent(d.section, () => []).add(d);
        }
        final changed = dials.where((d) => GameTuning.i.isOverridden(d.id));
        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                children: [
                  for (final s in sections.entries) ...[
                    _sectionHeader(s.key),
                    for (final d in s.value) _dialRow(d),
                    const SizedBox(height: 6),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
            _saveBar(changed.length),
          ],
        );
      },
    );
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 6),
    child: Row(
      children: [
        Text(
          title.toUpperCase(),
          style: FoE.label(size: 11).copyWith(
            color: FoE.gold,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(child: Divider(height: 1)),
      ],
    ),
  );

  Widget _dialRow(Dial d) {
    final value = GameTuning.i.raw(d.id);
    final overridden = GameTuning.i.isOverridden(d.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: FoE.panel(radius: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.label,
                      style: FoE.label(size: 13).copyWith(color: FoE.parchment),
                    ),
                    const SizedBox(height: 2),
                    Text(d.help, style: FoE.dim(size: 10)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 74,
                child: TextField(
                  key: ValueKey('dial-${d.id}'),
                  controller: _ctrls[d.id],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
                  ],
                  textAlign: TextAlign.right,
                  style: FoE.value(size: 14).copyWith(color: FoE.goldBright),
                  decoration: InputDecoration(
                    isDense: true,
                    suffixText: d.unit.isEmpty ? null : d.unit,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                  ),
                  onChanged: (s) => _onTyped(d, s),
                ),
              ),
            ],
          ),
          if (d.felt != null) ...[
            const SizedBox(height: 6),
            Text(
              d.felt!(value),
              style: FoE.label(size: 11).copyWith(color: FoE.gold),
            ),
          ],
          // Only a CHANGED dial carries this line — an untouched menu stays
          // quiet, and what you altered is visible at a glance.
          if (overridden) ...[
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () => _resetDial(d),
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  const Icon(Icons.undo, size: 13, color: FoE.textMuted),
                  const SizedBox(width: 4),
                  Text(
                    'Zurück auf ${_fmt(d.toField(d.def))}${d.unit}',
                    style: FoE.dim(size: 10),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _saveBar(int changedCount) => Container(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            changedCount == 0
                ? 'Alles auf den Startwerten.'
                : '$changedCount Wert${changedCount == 1 ? '' : 'e'} vom '
                    'Startwert abweichend.',
            style: FoE.dim(size: 11),
          ),
        ),
        GestureDetector(
          onTap: _saving ? null : _save,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
            decoration: FoE.btn(active: _dirty),
            child: Text(
              _saving ? '…' : 'Speichern',
              style: FoE.label(size: 13).copyWith(
                color: _dirty ? FoE.goldBright : FoE.textMuted,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
