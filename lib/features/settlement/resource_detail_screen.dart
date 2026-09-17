import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../common/widgets/filter_pills.dart';
import '../common/widgets/parchment_page.dart';
import 'data/building_definitions.dart';
import 'models/placed_building.dart';
import 'services/game_engine.dart';
import 'settlement_controller.dart';
import 'sheets/building_detail_dialog.dart';
import 'storage_detail_screen.dart';
import 'widgets/building_icon.dart';
import '../../core/ui/pressable.dart';

/// The resource-tap breakdown, now its OWN screen (user 2026-08-31: "die
/// Ressourcendetail screens einen eigenen Screen werden, welche ebenfalls
/// genau so aufgebaut sind [wie Housing/Work]") — replacing
/// [ResourceBreakdownSheet]'s bottom sheet.
///
/// Same shape as the Management screen's Housing/Work tabs: a header line
/// (a sort pill included), then one compact row per building — its own
/// asset, its name and level, what it contributes — tapping a row into the
/// SAME [showBuildingDetailDialog] those tabs open.
///
/// The store's own ceiling moved OUT to its own [StorageDetailScreen] (user
/// 2026-08-31: "das Lager nicht unten kommt, sondern wenn ich auf den in
/// store Balken drücke, dann komme ich auf die Lagerseite, welche genau
/// gleich aufgebaut ist") — the "In store" bar here is now the door into
/// it, not a section competing with the production list for the same page.
class ResourceDetailScreen extends StatefulWidget {
  final String resourceId;
  final String emoji;
  final String title;

  const ResourceDetailScreen({
    super.key,
    required this.resourceId,
    required this.emoji,
    required this.title,
  });

  @override
  State<ResourceDetailScreen> createState() => _ResourceDetailScreenState();
}

class _ResourceDetailScreenState extends State<ResourceDetailScreen> {
  final _ctrl = SettlementController();
  static final PillPalette _pills = PillPalette.parchment;

  /// Same convention as the Housing/Work tabs: null = by amount produced
  /// (the default), 'level' or 'name' otherwise, same field flips direction
  /// on a second tap.
  String? _sort;
  bool _descending = true;

  // ── The PAGE is built once; only its NUMBERS listen (user-report
  // 2026-08-31: pressing back out of this screen could hang on a black
  // screen) ──
  // This used to wrap the whole ParchmentPage — Scaffold, meander bands,
  // header and its back button included — in one AnimatedBuilder tied to
  // [_ctrl], which ticks every 5 s on its own passive-economy timer. That
  // tore down and rebuilt the ENTIRE page, back button included, on a
  // timer that keeps running while the pop transition is still playing —
  // every other pushed screen in the app (Management, the work/housing
  // tabs) builds its chrome once and only re-renders on its own setState.
  // Only [trailing] and [child] actually read [_ctrl], so only those two
  // listen now; the Scaffold/header/back-button/bands are built once per
  // State build, exactly like everywhere else.
  @override
  Widget build(BuildContext context) => ParchmentPage(
    title: '${widget.emoji}  ${widget.title}',
    trailing: AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final total = _ctrl.hourlyRates[widget.resourceId] ?? 0;
        return Text(
          '${total >= 0 ? '+' : ''}${total.toStringAsFixed(1)}/h',
          // A net loss is red, same rule the top bar's own cell follows
          // (user 2026-08-01) — the '+' cancels itself out on the one
          // number where the direction is the whole point otherwise.
          style: FoE.value(
            size: 14,
          ).copyWith(color: total < 0 ? FoE.danger : FoE.goldBright),
        );
      },
    ),
    child: AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final made = _ctrl.productionSourcesByBuilding(widget.resourceId)
          ..sort((a, b) {
            final cmp = switch (_sort) {
              'level' => a.$1.level.compareTo(b.$1.level),
              'name' => a.$2.name.compareTo(b.$2.name),
              _ => a.$3.compareTo(b.$3),
            };
            return _descending ? -cmp : cmp;
          });
        // The synthetic drains (refining, upkeep) — never tied to one
        // building, so they stay grouped/untappable, same as before.
        final eaten = _ctrl
            .productionSources(widget.resourceId)
            .where((s) => s.amount < 0)
            .toList();
        final stored = _ctrl.resources?.amountOf(widget.resourceId);
        final capacity = _ctrl.storageCapacity(widget.resourceId);
        final hasCap = stored != null && capacity > 0;
        final isFull = hasCap && stored >= capacity;
        final net =
            made.fold<double>(0, (a, s) => a + s.$3) +
            eaten.fold<double>(0, (a, s) => a + s.amount);

        return ListView(
          padding: const EdgeInsets.fromLTRB(
            ParchmentPage.kParchmentPagePad,
            12,
            ParchmentPage.kParchmentPagePad,
            20,
          ),
          children: [
            if (hasCap) ...[
              _storeButton(stored, capacity, isFull),
              const SizedBox(height: 14),
            ],
            if (made.isEmpty && eaten.isEmpty)
              Text(
                'Nothing is producing this yet.',
                style: FoE.dim(size: 12).copyWith(color: FoE.textDim),
              )
            else ...[
              if (made.isNotEmpty) ...[
                Row(
                  children: [
                    _heading('Produced by'),
                    const Spacer(),
                    // Flexible, not bare (2026-08-31 crash: "RenderFlex
                    // children have non-zero flex but incoming width
                    // constraints are unbounded") — [MenuPill] has an
                    // Expanded label INSIDE it, so it needs a bounded
                    // width from whatever Row it sits in.
                    Flexible(child: _sortPill()),
                  ],
                ),
                const SizedBox(height: 8),
                for (final s in made) _instanceRow(context, s),
                const SizedBox(height: 4),
              ],
              if (eaten.isNotEmpty) ...[
                const SizedBox(height: 8),
                _heading('Consumed by'),
                const SizedBox(height: 8),
                for (final s in eaten) _syntheticRow(s),
              ],
              _netRow(net),
            ],
          ],
        );
      },
    ),
  );

  Widget _heading(String text) => Text(
    text.toUpperCase(),
    style: FoE.label(size: 10).copyWith(color: FoE.gold, letterSpacing: 1.1),
  );

  /// Order "Produced by" by amount, by level, or by name — same
  /// field-picks-then-flips control the Housing/Work tabs use.
  Widget _sortPill() => MenuPill<String>(
    palette: _pills,
    icon: Icons.swap_vert,
    label: switch (_sort) {
      'level' => 'Level',
      'name' => 'Name',
      _ => 'Amount',
    },
    engaged: _sort != null || !_descending,
    value: _sort ?? '',
    entries: const [
      MapEntry('', 'Amount'),
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

  /// "In store", now the door into [StorageDetailScreen] rather than a
  /// section of this page (user 2026-08-31).
  Widget _storeButton(double stored, double capacity, bool isFull) =>
      Pressable(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StorageDetailScreen(
              resourceId: widget.resourceId,
              emoji: widget.emoji,
              title: widget.title,
            ),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: FoE.panel(radius: 10),
          child: Row(
            children: [
              // Just "Storage" (user 2026-08-31: "Hier auch nur Storage, den
              // Rest löschen") — no caption line, same as the section
              // heading and its sort pill on the page this opens.
              Expanded(child: Text('Storage', style: FoE.label(size: 12))),
              Text(
                '${stored.toStringAsFixed(0)} / ${capacity.toStringAsFixed(0)}',
                style: FoE.value(
                  size: 14,
                ).copyWith(color: isFull ? FoE.danger : FoE.goldBright),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 18, color: FoE.textDim),
            ],
          ),
        ),
      );

  /// WHAT IS ACTUALLY PRODUCED — the sum of every row above it, arrived at
  /// rather than asserted (if it ever disagrees with the header rate, a row
  /// is missing).
  ///
  /// A thicker rule now (user 2026-08-31), the same 2 px [ParchmentDivider]
  /// draws — not that widget itself, because it insets by
  /// [ParchmentPage.kParchmentPagePad] on the assumption of NO ambient
  /// padding, and this row already sits inside the page's own padded
  /// ListView; a second inset here would pull it in twice.
  Widget _netRow(double net) => Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.only(top: 10),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: FoE.border, width: 2)),
    ),
    child: Row(
      children: [
        // "Total", not "Net gain"/"Net loss" (user 2026-08-31) — one label
        // regardless of sign; the number and its colour already say which.
        Expanded(
          child: Text(
            'Total',
            style: FoE.label(size: 13).copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        Text(
          '${net > 0 ? '+' : ''}${net.toStringAsFixed(1)}/h',
          style: FoE.value(
            size: 14,
          ).copyWith(color: net < 0 ? FoE.danger : FoE.goldBright),
        ),
      ],
    ),
  );

  /// The Housing/Work tab's own row shape, for a real building: its asset,
  /// centred and big, its name and level, and what it contributes here —
  /// tapping it into the same building detail dialog those tabs use.
  Widget _instanceRow(
    BuildContext context,
    (PlacedBuilding, BuildingDef, double) s,
  ) {
    final (b, def, amount) = s;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Pressable(
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
                '+${amount.toStringAsFixed(1)}/h',
                style: FoE.value(size: 12).copyWith(color: FoE.gold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A drain not tied to any one building (refining, creature upkeep) — the
  /// same row shape, minus the tap and the level line it has nothing to
  /// show for either.
  Widget _syntheticRow(ProductionSource s) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: FoE.panel(radius: 8),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Center(
              child: BuildingIcon(
                imageUrl: s.imageUrl,
                defId: s.defId,
                emoji: s.emoji,
                size: 56,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              s.count > 1 ? '${s.label} ×${s.count}' : s.label,
              style: FoE.label(size: 13),
            ),
          ),
          Text(
            '${s.amount.toStringAsFixed(1)}/h',
            style: FoE.value(size: 12).copyWith(color: FoE.danger),
          ),
        ],
      ),
    ),
  );
}
