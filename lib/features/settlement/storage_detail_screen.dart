import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../common/widgets/filter_pills.dart';
import '../common/widgets/parchment_page.dart';
import '../common/widgets/recess_bar.dart';
import 'data/building_definitions.dart';
import 'models/placed_building.dart';
import 'settlement_controller.dart';
import 'sheets/building_detail_dialog.dart';
import 'widgets/building_icon.dart';
import 'widgets/scroll_paper.dart' show kActionGreen;

/// "Wo kommt der Lagerplatz her" — the Resource screen's "In store" bar
/// opens THIS now instead of a section at the bottom of that page (user
/// 2026-08-31: "das Lager nicht unten kommt, sondern wenn ich auf den in
/// store Balken drücke, dann komme ich auf die Lagerseite, welche genau
/// gleich aufgebaut ist"). Genau gleich: the Housing/Work tabs' own shape —
/// a header line with a sort pill, then one row per building, tapping a row
/// into the same [showBuildingDetailDialog] those tabs open.
class StorageDetailScreen extends StatefulWidget {
  final String resourceId;
  final String emoji;
  final String title;

  const StorageDetailScreen({
    super.key,
    required this.resourceId,
    required this.emoji,
    required this.title,
  });

  @override
  State<StorageDetailScreen> createState() => _StorageDetailScreenState();
}

class _StorageDetailScreenState extends State<StorageDetailScreen> {
  final _ctrl = SettlementController();
  static final PillPalette _pills = PillPalette.parchment;

  /// Same convention as every other sort pill in Management: null = by room
  /// contributed (the default), 'level' or 'name' otherwise.
  String? _sort;
  bool _descending = true;

  // Page built once, only the numbers listen — see the matching note on
  // ResourceDetailScreen.build() (user-report 2026-08-31: pressing back
  // could hang on a black screen). The whole ParchmentPage — Scaffold,
  // bands, header and its back button — used to live inside one
  // AnimatedBuilder tied to [_ctrl]'s 5 s tick; now only [trailing] and
  // [child] do.
  @override
  Widget build(BuildContext context) => ParchmentPage(
    title: '${widget.emoji}  ${widget.title} storage',
    trailing: AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final stored = _ctrl.resources?.amountOf(widget.resourceId) ?? 0;
        final capacity = _ctrl.storageCapacity(widget.resourceId);
        final isFull = capacity > 0 && stored >= capacity;
        return Text(
          '${stored.toStringAsFixed(0)}/${capacity.toStringAsFixed(0)}',
          style: FoE.value(
            size: 14,
          ).copyWith(color: isFull ? FoE.danger : FoE.goldBright),
        );
      },
    ),
    child: AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final stored = _ctrl.resources?.amountOf(widget.resourceId) ?? 0;
        final capacity = _ctrl.storageCapacity(widget.resourceId);
        final isFull = capacity > 0 && stored >= capacity;
        final frac = capacity > 0 ? (stored / capacity).clamp(0.0, 1.0) : 1.0;
        // The settlement's own base — never tied to a building, so it is not
        // part of the sortable list, just the fixed first line under the bar.
        final baseCap =
            capacity -
            _ctrl
                .storageSourcesByBuilding(widget.resourceId)
                .fold<double>(0, (a, s) => a + s.$3);
        final buildings = _ctrl.storageSourcesByBuilding(widget.resourceId)
          ..sort((a, b) {
            final cmp = switch (_sort) {
              'level' => a.$1.level.compareTo(b.$1.level),
              'name' => a.$2.name.compareTo(b.$2.name),
              _ => a.$3.compareTo(b.$3),
            };
            return _descending ? -cmp : cmp;
          });

        return ListView(
          padding: const EdgeInsets.fromLTRB(
            ParchmentPage.kParchmentPagePad,
            12,
            ParchmentPage.kParchmentPagePad,
            20,
          ),
          children: [
            // No box around the bar any more (user 2026-08-31: "mache diesen
            // Balken ohne die Box drum herum beim Storage") — the bar and its
            // n/n note are the whole story, the panel around them was one
            // more surface saying "these two belong together" that the two
            // lines already said on their own.
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RecessBar(
                  value: frac,
                  color: isFull ? FoE.danger : kActionGreen,
                  height: 10,
                ),
                const SizedBox(height: 6),
                // Just the number (user 2026-08-31: "'room for n' more
                // löschen, dafür unten rechts die Anzeige n/n") — the
                // header already carries this same figure, but it also
                // has to be a bottom-right note.
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${stored.toStringAsFixed(0)}/${capacity.toStringAsFixed(0)}',
                    style: FoE.dim(
                      size: 10,
                    ).copyWith(color: isFull ? FoE.danger : FoE.textDim),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'STORAGE',
                  style: FoE.label(
                    size: 10,
                  ).copyWith(color: FoE.gold, letterSpacing: 1.1),
                ),
                const Spacer(),
                // Flexible, not bare (2026-08-31 crash: "RenderFlex children
                // have non-zero flex but incoming width constraints are
                // unbounded") — [MenuPill] has an Expanded label inside it.
                if (buildings.isNotEmpty) Flexible(child: _sortPill()),
              ],
            ),
            const SizedBox(height: 8),
            if (baseCap > 0) _baseRow(baseCap),
            for (final s in buildings) _instanceRow(context, s),
          ],
        );
      },
    ),
  );

  Widget _sortPill() => MenuPill<String>(
    palette: _pills,
    icon: Icons.swap_vert,
    label: switch (_sort) {
      'level' => 'Level',
      'name' => 'Name',
      _ => 'Storage',
    },
    engaged: _sort != null || !_descending,
    value: _sort ?? '',
    entries: const [
      MapEntry('', 'Storage'),
      MapEntry('level', 'Level'),
      MapEntry('name', 'Name'),
    ],
    trailing: Icon(
      _descending ? Icons.arrow_downward : Icons.arrow_upward,
      size: 14,
      color: FoE.gold,
    ),
    selectedTrailing: _descending ? '↓' : '↑',
    onSelected: (v) {
      final picked = v.isEmpty ? null : v;
      setState(() {
        if (picked == _sort) {
          _descending = !_descending;
        } else {
          _sort = picked;
          _descending = true;
        }
      });
    },
  );

  /// The settlement's own base capacity — not a building, so no icon lane
  /// or tap, just the same row shape's text and number.
  Widget _baseRow(double amount) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: FoE.panel(radius: 8),
      child: Row(
        children: [
          const SizedBox(
            width: 64,
            child: Center(child: Text('🏛', style: TextStyle(fontSize: 28))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text('The settlement itself', style: FoE.label(size: 13)),
          ),
          Text(
            '+${amount.toStringAsFixed(0)}',
            style: FoE.value(size: 12).copyWith(color: FoE.gold),
          ),
        ],
      ),
    ),
  );

  Widget _instanceRow(
    BuildContext context,
    (PlacedBuilding, BuildingDef, double) s,
  ) {
    final (b, def, amount) = s;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showBuildingDetailDialog(context, _ctrl, b),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: FoE.panel(radius: 8),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                child: Center(
                  child: BuildingIcon(
                    imageUrl: def.imageUrl,
                    defId: def.id,
                    size: 56,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(def.name, style: FoE.label(size: 13)),
                    Text(
                      'Lv ${b.level}',
                      style: FoE.dim(size: 11).copyWith(color: FoE.gold),
                    ),
                  ],
                ),
              ),
              Text(
                '+${amount.toStringAsFixed(0)}',
                style: FoE.value(size: 12).copyWith(color: FoE.gold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
