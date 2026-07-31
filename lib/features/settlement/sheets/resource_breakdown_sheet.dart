import 'package:flutter/material.dart';
import '../../../core/theme/foe_theme.dart';
import '../services/game_engine.dart';
import '../widgets/building_icon.dart';
import '../widgets/parchment_sheet.dart';
import '../widgets/scroll_paper.dart' show kActionGreen;
import '../../common/widgets/recess_bar.dart';

// Tap target for every resource cell in the top bar — shows exactly which
// buildings contribute to that resource's rate, grouped by building type
// (a settlement with 3 Lumber Camps shows one "Lumber Camp ×3" row, not
// three identical rows). Entries always sum to the header rate/count exactly
// since GameEngine.productionSources/populationSources use the same bonus
// math as hourlyRates/computeWorkforce, just broken out per building.
//
// Wrapped in a DraggableScrollableSheet (same pattern as the other sheets:
// PopulationOverviewSheet) — the header stays put while the source list
// scrolls via ListView's own controller, so it's always fully reachable
// regardless of how many buildings contribute.
class ResourceBreakdownSheet extends StatelessWidget {
  final String emoji;
  final String title;
  final double total;
  final String unit; // e.g. '/h' or ' residents'
  final List<ProductionSource> sources;

  /// THE CEILING, and how much of it is used (user 2026-07-30: "wenn ich oben
  /// auf die Ressourcen drücke, will ich auch das Cap sehen").
  ///
  /// A rate answers "how fast"; it does not answer "and then what". Since
  /// production STOPS at the ceiling, a sheet that shows +12/h while the store
  /// has been full for an hour is describing something that is not happening.
  /// Both null for the cells that have no ceiling — energy and housing.
  final double? stored;
  final double? capacity;

  /// Where the room comes from, listed like the rate's sources are.
  final List<ProductionSource> capacitySources;

  const ResourceBreakdownSheet({
    super.key,
    required this.emoji,
    required this.title,
    required this.total,
    required this.unit,
    required this.sources,
    this.stored,
    this.capacity,
    this.capacitySources = const [],
  });

  bool get _hasCap => capacity != null && stored != null && capacity! > 0;
  bool get _isFull => _hasCap && stored! >= capacity!;

  @override
  Widget build(BuildContext context) {
    return ParchmentSheet(
      title: '$emoji  $title',
      initialSize: 0.5,
      minSize: 0.3,
      maxSize: 0.9,
      trailing: Text(
        '${total >= 0 ? '+' : ''}${total.toStringAsFixed(1)}$unit',
        style: FoE.value(size: 14).copyWith(color: ParchmentSheet.accent),
      ),
      builder: (context, scrollCtrl) => ListView(
        controller: scrollCtrl,
        padding: const EdgeInsets.fromLTRB(26, 4, 26, 20),
        children: [
          // THE STORE FIRST. When it is full the rate above is a promise the
          // settlement is not keeping, so the reason has to arrive before the
          // list of things making it.
          if (_hasCap) ...[
            _storageBlock(),
            const SizedBox(height: 14),
          ],
          if (sources.isEmpty)
            Text(
              'Nothing is producing this yet.',
              style: FoE.dim(size: 11).copyWith(color: ParchmentSheet.inkFaint),
            )
          else ...[
            _heading('Produced by'),
            for (final s in sources) _sourceRow(s),
          ],
          if (capacitySources.isNotEmpty) ...[
            const SizedBox(height: 14),
            _heading('Room from'),
            for (final s in capacitySources)
              _sourceRow(s, unitOverride: ''),
          ],
        ],
      ),
    );
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text.toUpperCase(),
      style: FoE.label(size: 10).copyWith(
        color: ParchmentSheet.accent,
        letterSpacing: 1.1,
      ),
    ),
  );

  /// Held / room, with the bar that says how close the two are.
  Widget _storageBlock() {
    final frac = (stored! / capacity!).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'In store',
              style: FoE.label(size: 12).copyWith(color: ParchmentSheet.ink),
            ),
            const Spacer(),
            Text(
              '${stored!.toStringAsFixed(0)} / ${capacity!.toStringAsFixed(0)}',
              style: FoE.value(size: 13).copyWith(
                color: _isFull
                    ? const Color(0xFF9B3B22)
                    : ParchmentSheet.ink,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        RecessBar(
          value: frac,
          color: _isFull ? const Color(0xFF9B3B22) : kActionGreen,
          height: 10,
        ),
        const SizedBox(height: 6),
        Text(
          _isFull
              // The one thing a full store must not do is stop production
              // quietly — the rate in the header is still ticking over.
              ? 'Full — production of this has stopped. Build or level a store '
                  'to make room.'
              : 'Room for ${(capacity! - stored!).toStringAsFixed(0)} more. '
                  'Production stops at the ceiling.',
          style: FoE.dim(size: 10).copyWith(
            color: _isFull
                ? const Color(0xFF9B3B22)
                : ParchmentSheet.inkFaint,
          ),
        ),
      ],
    );
  }

  Widget _sourceRow(ProductionSource s, {String? unitOverride}) {
    final isNegative = s.amount < 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          BuildingIcon(imageUrl: s.imageUrl, emoji: s.emoji, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              s.count > 1 ? '${s.label} ×${s.count}' : s.label,
              style: FoE.label(size: 13),
            ),
          ),
          Text(
            '${isNegative ? '' : '+'}${s.amount.toStringAsFixed(1)}'
            '${unitOverride ?? unit}',
            style: FoE.value(
              size: 12,
            ).copyWith(color: isNegative ? Colors.redAccent : FoE.gold),
          ),
        ],
      ),
    );
  }
}
