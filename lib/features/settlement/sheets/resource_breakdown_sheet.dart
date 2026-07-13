import 'package:flutter/material.dart';
import '../../../core/theme/foe_theme.dart';
import '../services/game_engine.dart';
import '../widgets/building_icon.dart';

// Tap target for every resource cell in the top bar — shows exactly which
// buildings contribute to that resource's rate, grouped by building type
// (a settlement with 3 Lumber Camps shows one "Lumber Camp ×3" row, not
// three identical rows). Entries always sum to the header rate/count exactly
// since GameEngine.productionSources/populationSources use the same bonus
// math as hourlyRates/computeWorkforce, just broken out per building.
//
// Wrapped in a DraggableScrollableSheet (same pattern as BuildMenuSheet/
// PopulationOverviewSheet) — the header stays put while the source list
// scrolls via ListView's own controller, so it's always fully reachable
// regardless of how many buildings contribute.
class ResourceBreakdownSheet extends StatelessWidget {
  final String emoji;
  final String title;
  final double total;
  final String unit; // e.g. '/h' or ' residents'
  final List<ProductionSource> sources;

  const ResourceBreakdownSheet({
    super.key,
    required this.emoji,
    required this.title,
    required this.total,
    required this.unit,
    required this.sources,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollCtrl) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: Container(
          decoration: const BoxDecoration(
            gradient: FoE.panelGradient,
            border: Border(top: BorderSide(color: FoE.borderGold, width: 1.5)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: FoE.borderGold,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(title, style: FoE.title(size: 16))),
                    Text(
                      '${total >= 0 ? '+' : ''}${total.toStringAsFixed(1)}$unit',
                      style: FoE.value(
                        size: 14,
                      ).copyWith(color: FoE.goldBright),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FoE.divider(vPad: 8),
              ),
              Expanded(
                child: sources.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        child: Text(
                          'Nothing is producing this yet.',
                          style: FoE.dim(size: 11).copyWith(color: FoE.textDim),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                        itemCount: sources.length,
                        itemBuilder: (_, i) => _sourceRow(sources[i]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sourceRow(ProductionSource s) {
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
            '${isNegative ? '' : '+'}${s.amount.toStringAsFixed(1)}$unit',
            style: FoE.value(
              size: 12,
            ).copyWith(color: isNegative ? Colors.redAccent : FoE.gold),
          ),
        ],
      ),
    );
  }
}
