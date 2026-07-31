import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;

import '../data/resource_icons.dart';
import '../../../core/theme/foe_theme.dart';
import '../data/gather_defs.dart';
import '../data/goods_definitions.dart';
import '../services/game_defs_controller.dart';

/// Dev Mode → Resources: the four dials that decide what an expedition is worth
/// (user 2026-07-25).
///
/// One row per resource, because that is the level the questions live at —
/// "wieviel Gewicht entspricht ein Punkt Carry", "wie viel Holz hat ein
/// Holz-Spot", "welche Nachfüllrate", "wie lange dauert 1 Einheit pro
/// Statpunkt". They used to be spread over every spot in every area (three of
/// them) plus a global reference constant in code (the fourth).
///
/// Each row previews what the numbers MEAN for a real group, because none of
/// the four is legible on its own: 3000 s/unit/stat says nothing, "228/h with a
/// 190-point group" says everything.
class GatherDefsTab extends StatefulWidget {
  const GatherDefsTab({super.key});

  @override
  State<GatherDefsTab> createState() => _GatherDefsTabState();
}

class _GatherDefsTabState extends State<GatherDefsTab> {
  /// The example group the previews are computed for — editable, so the
  /// numbers can be read against the monsters actually in play.
  double _gatherStat = 190;
  double _carryStat = 15;

  String? _saving;

  Future<void> _save(ResourceGatherDef def) async {
    setState(() => _saving = def.resource);
    try {
      await GameDefsController().saveGatherDef(def);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
    if (mounted) setState(() => _saving = null);
  }

  @override
  Widget build(BuildContext context) {
    final resources = gatherTunableResources();
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _groupPanel(),
        const SizedBox(height: 14),
        for (final r in resources) _resourceCard(r),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _groupPanel() => Container(
    padding: const EdgeInsets.all(12),
    decoration: FoE.panel(radius: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sample group (preview only)',
            style: FoE.label(size: 13).copyWith(color: FoE.gold)),
        Text(
          'The numbers below are worked out for this group — it is not saved.',
          style: FoE.dim(size: 10),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _numField(
                label: 'Summe Abbau-Stat',
                value: _gatherStat,
                onChanged: (v) => setState(() => _gatherStat = v),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _numField(
                label: 'Summed carry stat',
                value: _carryStat,
                onChanged: (v) => setState(() => _carryStat = v),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _resourceCard(String resource) {
    final def = gatherDefFor(resource);
    final emoji = resourceEmoji(resource);
    final name = kGoodsDefs[resource]?.name ?? _title(resource);
    final authored = kGatherDefs.containsKey(resource);

    final rate = def.ratePerHour(_gatherStat);
    final cap = def.loadCap(_carryStat);
    final tripHours = rate > 0 ? cap / rate : 0.0;
    // A spot only holds so much: a trip can never haul more than what's there.
    final haul = cap > def.spotCapacity ? def.spotCapacity : cap;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: FoE.panel(radius: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(child: Text(name, style: FoE.title(size: 14))),
              if (!authored)
                Text('Standard', style: FoE.dim(size: 10)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _numField(
                  label: 'Units per carry point',
                  value: def.unitsPerCarry,
                  onChanged: (v) =>
                      _save(def.copyWith(unitsPerCarry: v)),
                  commitOnSubmit: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _numField(
                  label: 'Seconds per unit & stat point',
                  value: def.secondsPerUnitPerStat,
                  onChanged: (v) =>
                      _save(def.copyWith(secondsPerUnitPerStat: v)),
                  commitOnSubmit: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _numField(
                  label: 'Amount per spot',
                  value: def.spotCapacity,
                  onChanged: (v) => _save(def.copyWith(spotCapacity: v)),
                  commitOnSubmit: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _numField(
                  label: 'Refill rate /h',
                  value: def.regenPerHour,
                  onChanged: (v) => _save(def.copyWith(regenPerHour: v)),
                  commitOnSubmit: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: FoE.panelDark,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _previewRow('Abbau', '${_fmt(rate)}/h'),
                _previewRow('Tragen', '${_fmt(cap)} pro Trip'),
                _previewRow(
                  'Eine volle Fuhre',
                  rate <= 0
                      ? '—'
                      : '${_fmt(haul)} in ${_fmtHours(haul / rate)}'
                          '${cap > def.spotCapacity ? ' (Spot leer)' : ''}',
                ),
                _previewRow(
                  'Spot voll nach',
                  def.regenPerHour <= 0
                      ? 'nie'
                      : _fmtHours(def.spotCapacity / def.regenPerHour),
                ),
                if (_saving == resource)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Speichern…', style: FoE.dim(size: 10)),
                  ),
                if (tripHours > 12)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'A full load takes over 12 h — longer than a player waits.',
                      style: FoE.dim(size: 10).copyWith(color: FoE.danger),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(
      children: [
        Text(label, style: FoE.dim(size: 11)),
        const Spacer(),
        Text(value, style: FoE.value(size: 12)),
      ],
    ),
  );

  /// A number field. [commitOnSubmit] saves on Enter/blur instead of on every
  /// keystroke — these write to Supabase, so per-character saves would fire a
  /// request per digit.
  Widget _numField({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    bool commitOnSubmit = false,
  }) => TextFormField(
    key: ValueKey('$label-$value'),
    initialValue: _fmt(value),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
    style: FoE.label(size: 14).copyWith(color: FoE.parchment),
    decoration: InputDecoration(labelText: label, isDense: true),
    onFieldSubmitted: commitOnSubmit
        ? (s) {
            final v = double.tryParse(s);
            if (v != null && v > 0) onChanged(v);
          }
        : null,
    onChanged: commitOnSubmit
        ? null
        : (s) {
            final v = double.tryParse(s);
            if (v != null && v > 0) onChanged(v);
          },
  );

  static String _title(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  static String _fmtHours(double hours) {
    if (hours <= 0) return '—';
    final total = (hours * 60).round();
    final h = total ~/ 60;
    final m = total % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}
