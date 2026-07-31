import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../../core/theme/foe_theme.dart';
import '../../../core/tuning/game_tuning.dart';
import '../../creatures/models/ability_def.dart';
import '../../creatures/models/area.dart';
import '../../creatures/models/path_node.dart';
import '../../creatures/models/species_balance.dart';
import '../../creatures/models/species_def.dart';
import '../../creatures/models/xp_balance.dart';
import '../data/building_definitions.dart';
import '../data/era_definitions.dart';
import '../data/gather_defs.dart';
import '../data/item_definitions.dart';

// ── Getting the tuned state OUT (user 2026-07-29) ──────────────────────────
// "Ich will 'unabhängig' von dir sein. Alles was ich im Devmode eingebe, soll
// direkt übernommen werden für alle."
//
// The database IS the live truth, and that is what makes the author
// independent. What was missing is the other direction: nothing could read the
// tuned state back OUT, so a config someone spent an evening on was invisible
// to the repo, unreviewable, and gone with the row.
//
// One tap per subject, JSON on the clipboard, in exactly the shape the loaders
// parse (`toDefRow()`). Per subject rather than one giant blob on purpose: the
// building roster alone is far too big to paste into a chat, and "the numbers"
// — the thing that actually gets retuned — is a couple of lines.
class DevExportSheet extends StatelessWidget {
  const DevExportSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const DevExportSheet(),
  );

  /// Everything that is exportable, newest-thinking first: the dials, then the
  /// defs, in the order the menus list them.
  List<_Export> _exports() => [
    _Export(
      '⚙️',
      'Werte (alle Regler)',
      'Settlement, Kampagne und Monster — nur, was vom Startwert abweicht.',
      () => {
        for (final g in TuningGroup.values)
          g.configKey: {
            for (final d in kDials)
              if (d.group == g && GameTuning.i.isOverridden(d.id))
                d.id: GameTuning.i.raw(d.id),
          },
      },
    ),
    _Export(
      '⚖️',
      'Budgets & XP',
      'Stat-Budgets pro Seltenheit, Brutdauern, XP-Kurve.',
      () => {
        'species_balance': kSpeciesBalance.toJson(),
        'xp_balance': kXpBalance.toJson(),
      },
    ),
    _Export(
      '🏠',
      'Gebäude',
      '${kBuildingDefs.length} Gebäude mit allen Effekten.',
      () => {for (final e in kBuildingDefs.entries) e.key: e.value.toDefRow()},
    ),
    _Export(
      '🐾',
      'Arten',
      '${kSpeciesDefs.length} Monsterarten.',
      () => {for (final e in kSpeciesDefs.entries) e.key: e.value.toDefRow()},
    ),
    _Export(
      '✨',
      'Abilities',
      '${kAbilityDefs.length} Fähigkeiten.',
      () => {for (final e in kAbilityDefs.entries) e.key: e.value.toDefRow()},
    ),
    _Export(
      '🗺',
      'Pfad',
      '${kPathNodes.length} Stationen der Kampagne.',
      () => {for (final e in kPathNodes.entries) e.key: e.value.toDefRow()},
    ),
    _Export(
      '🏞',
      'Gebiete',
      '${kAreaDefs.length} Gebiete.',
      () => {for (final e in kAreaDefs.entries) e.key: e.value.toDefRow()},
    ),
    _Export(
      '🎒',
      'Items',
      '${kItemDefs.length} Gegenstände.',
      () => {for (final e in kItemDefs.entries) e.key: e.value.toDefRow()},
    ),
    _Export(
      '⛏',
      'Ressourcen',
      '${kGatherDefs.length} Abbau-Einstellungen.',
      () => {for (final e in kGatherDefs.entries) e.key: e.value.toDefRow()},
    ),
    _Export(
      '🏺',
      'Äras',
      '${kEraDefs.length} Ären.',
      () => {for (final e in kEraDefs.entries) e.key: e.value.toDefRow()},
    ),
  ];

  Future<void> _copy(BuildContext context, _Export e) async {
    final messenger = ScaffoldMessenger.of(context);
    String text;
    try {
      text = const JsonEncoder.withIndent('  ').convert(e.build());
    } catch (err) {
      messenger.showSnackBar(
        SnackBar(content: Text('Export fehlgeschlagen: $err')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(
      SnackBar(
        content: Text('${e.title} kopiert — ${_size(text.length)}.'),
        backgroundColor: FoE.positive,
      ),
    );
  }

  static String _size(int chars) =>
      chars < 2000 ? '$chars Zeichen' : '${(chars / 1024).round()} KB';

  @override
  Widget build(BuildContext context) {
    final items = _exports();
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: FoE.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Export', style: FoE.title(size: 16)),
          const SizedBox(height: 2),
          Text(
            'Kopiert den aktuellen Stand als JSON in die Zwischenablage — '
            'genau so, wie ihn das Spiel lädt.',
            style: FoE.dim(size: 11),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, i) {
                final e = items[i];
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _copy(context, e),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: FoE.panel(radius: 8),
                    child: Row(
                      children: [
                        Text(e.emoji, style: const TextStyle(fontSize: 17)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.title,
                                style: FoE.label(size: 13)
                                    .copyWith(color: FoE.parchment),
                              ),
                              const SizedBox(height: 2),
                              Text(e.subtitle, style: FoE.dim(size: 10)),
                            ],
                          ),
                        ),
                        const Icon(Icons.copy, size: 17, color: FoE.gold),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Export {
  final String emoji;
  final String title;
  final String subtitle;

  /// Built on TAP, not up front: serialising the whole building roster to
  /// count its characters would be paid every time the sheet opens.
  final Map<String, dynamic> Function() build;
  const _Export(this.emoji, this.title, this.subtitle, this.build);
}
