import 'package:flutter/material.dart';
import '../../../core/theme/foe_theme.dart';
import '../../creatures/dev/ability_def_form.dart';
import '../../creatures/dev/species_def_form.dart';
import '../../creatures/models/ability_def.dart';
import '../../creatures/models/species_def.dart';
import '../data/building_definitions.dart';
import '../data/era_definitions.dart';
import '../data/tech_definitions.dart';
import '../widgets/building_icon.dart';
import 'balance_simulator_screen.dart';
import 'building_def_form.dart';
import 'dev_theme.dart';
import 'era_def_form.dart';
import 'tech_def_form.dart';

// All tabs are fully wired: Buildings -> BuildingDefForm, Tech -> TechDefForm,
// Eras -> EraDefForm, Species -> SpeciesDefForm, Abilities -> AbilityDefForm.
class DevModeScreen extends StatelessWidget {
  const DevModeScreen({super.key});

  void _openBuildingForm(BuildContext context, BuildingDef? existing) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BuildingDefForm(existing: existing)),
    );
  }

  void _openTechForm(BuildContext context, TechDef? existing) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TechDefForm(existing: existing)),
    );
  }

  void _openEraForm(BuildContext context, EraDef? existing) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EraDefForm(existing: existing)),
    );
  }

  void _openSpeciesForm(BuildContext context, SpeciesDef? existing) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SpeciesDefForm(existing: existing)),
    );
  }

  void _openAbilityForm(BuildContext context, AbilityDef? existing) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AbilityDefForm(existing: existing)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildDevModeTheme(),
      child: DefaultTabController(
        length: 6,
        child: Scaffold(
          backgroundColor: FoE.bg,
          appBar: AppBar(
            title: Text('🛠 Dev Mode', style: FoE.title(size: 16)),
            bottom: const TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'Buildings'),
                Tab(text: 'Tech'),
                Tab(text: 'Eras'),
                Tab(text: 'Species'),
                Tab(text: 'Abilities'),
                Tab(text: 'Balance'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _DefList(
                items: kBuildingDefs.values
                    .map(
                      (d) =>
                          _DefRow(imageUrl: d.imageUrl, name: d.name, id: d.id),
                    )
                    .toList(),
                onNew: () => _openBuildingForm(context, null),
                onTap: (id) => _openBuildingForm(context, kBuildingDefs[id]),
              ),
              _DefList(
                items: kTechDefs.values
                    .map((d) => _DefRow(emoji: d.emoji, name: d.name, id: d.id))
                    .toList(),
                onNew: () => _openTechForm(context, null),
                onTap: (id) => _openTechForm(context, kTechDefs[id]),
              ),
              _DefList(
                items:
                    (kEraDefs.values.toList()
                          ..sort((a, b) => a.order.compareTo(b.order)))
                        .map(
                          (d) => _DefRow(
                            emoji: d.emoji,
                            name: '${d.order}. ${d.name}',
                            id: d.id,
                          ),
                        )
                        .toList(),
                onNew: () => _openEraForm(context, null),
                onTap: (id) => _openEraForm(context, kEraDefs[id]),
              ),
              _DefList(
                items: kSpeciesDefs.values
                    .map(
                      (d) => _DefRow(
                        imageUrl: d.stageAt(0).imageUrl,
                        emoji: d.element.emoji,
                        name: '${d.name} · ${d.rarity.label}',
                        id: d.id,
                      ),
                    )
                    .toList(),
                onNew: () => _openSpeciesForm(context, null),
                onTap: (id) => _openSpeciesForm(context, kSpeciesDefs[id]),
              ),
              _DefList(
                items: kAbilityDefs.values
                    .map(
                      (d) => _DefRow(
                        emoji: d.element?.emoji ?? '⚔️',
                        name: '${d.name} · ${d.kind.label}',
                        id: d.id,
                      ),
                    )
                    .toList(),
                onNew: () => _openAbilityForm(context, null),
                onTap: (id) => _openAbilityForm(context, kAbilityDefs[id]),
              ),
              const BalanceSimulatorScreen(),
            ],
          ),
        ),
      ),
    );
  }
}

class _DefRow {
  final String emoji;
  final String? imageUrl;
  final String name;
  final String id;
  const _DefRow({
    this.emoji = '',
    this.imageUrl,
    required this.name,
    required this.id,
  });
}

class _DefList extends StatelessWidget {
  final List<_DefRow> items;
  final VoidCallback onNew;
  final ValueChanged<String> onTap;
  const _DefList({
    required this.items,
    required this.onNew,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: onNew,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: FoE.btn(active: true),
                child: Center(
                  child: Text(
                    '+ New',
                    style: FoE.label(size: 15).copyWith(color: FoE.goldBright),
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (_, i) {
              final item = items[i];
              return GestureDetector(
                onTap: () => onTap(item.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: FoE.panel(radius: 8),
                  child: Row(
                    children: [
                      BuildingIcon(
                        imageUrl: item.imageUrl,
                        emoji: item.emoji,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: FoE.label(
                                size: 15,
                              ).copyWith(color: FoE.parchment),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.id,
                              style: FoE.label(
                                size: 12,
                              ).copyWith(color: FoE.gold),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        color: FoE.parchment,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
