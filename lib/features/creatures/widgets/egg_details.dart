import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/foe_theme.dart';
import '../../settlement/widgets/scroll_paper.dart' show kParchmentInk;
import '../creature_detail_screen.dart';
import '../models/breeding_job.dart';
import '../models/creature_enums.dart';
import '../models/creature_instance.dart';
import '../models/species_def.dart';
import '../services/creature_power.dart';
import '../services/creatures_controller.dart';
import 'gene_bar_toggle.dart';
import '../../common/widgets/recess_bar.dart';

/// WHAT IS INSIDE AN EGG — the two blocks that answer it, shared by the
/// Hatchery's slot panel and the bag's egg screen (user 2026-07-27: the bag's
/// eggs open "ein neues Menü, welches das Ei zusammen mit den Stats zeigt").
///
/// They were private methods on the Hatchery's State. The bag needed the same
/// two blocks verbatim — an egg's genes are the same facts wherever you read
/// them — so they moved here rather than being copied, which is how the two
/// screens would have drifted apart on the first tweak.

/// The parchment screens' accent gold, as every page reached from a building
/// declares it.
const Color _kAccent = FoE.gold;
final Color _kInkSoft = kParchmentInk.withValues(alpha: 0.78);
final Color _kInkFaint = kParchmentInk.withValues(alpha: 0.55);
final Color _kCardFill = kParchmentInk.withValues(alpha: 0.06);

/// WHO MADE IT AND WHEN (user 2026-07-27). Two facts the genes cannot give you:
/// which pair this came from, and how long it has been sitting.
///
/// The two parents are CARDS side by side, which is what they are: a pair, each
/// an object you can open. The section caption carries the laid time on its
/// right, so it costs two lines rather than four.
///
/// A parent that has since been released, evolved or sold reads "gone" rather
/// than blanking the row: the egg keeps its ids for life, and the child inside
/// it was frozen when it was laid, so a missing parent changes nothing about
/// the egg — it is only a name we can no longer print.
class EggFacts extends StatelessWidget {
  final BreedingJob job;

  const EggFacts({super.key, required this.job});

  /// How long ago, coarsely. An egg can sit in the bag for days, and "72h 14m"
  /// is a countdown's precision on a number nothing depends on.
  static String ageLabel(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inDays >= 1) return '${d.inDays}d';
    if (d.inHours >= 1) return '${d.inHours}h';
    return '${d.inMinutes.clamp(0, 59)}m';
  }

  @override
  Widget build(BuildContext context) {
    // Parent A is the father — BreedingController.start sorts the pair that way
    // before the insert, so the cards can be printed ♂ then ♀ without a lookup.
    final creatures = CreaturesController();
    final dad = creatures.byId(job.parentAId);
    final mum = creatures.byId(job.parentBId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'PARENTS',
              style: FoE.dim(size: 9).copyWith(
                color: _kInkFaint,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            const Spacer(),
            // readyAt on an `egg` row is the moment the mating finished — when
            // it was laid. It has no running clock of its own.
            Text(
              'laid ${ageLabel(job.readyAt)} ago',
              style: FoE.dim(size: 10).copyWith(color: _kInkFaint),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // IntrinsicHeight, NOT CrossAxisAlignment.stretch (2026-07-27). This Row
        // lives in a Column inside a ListView, so its incoming height is
        // UNBOUNDED — and `stretch` lays children out at `constraints.maxHeight`,
        // which there is infinity. That is what produced the flood of "Cannot
        // hit test a render box that has never been laid out".
        //
        // IntrinsicHeight measures the taller card first and gives both that
        // height, which is what "stretch" was reaching for. It costs an extra
        // layout pass over two small cards.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _ParentCard(c: dad, gender: CreatureGender.male)),
              const SizedBox(width: 8),
              Expanded(
                child: _ParentCard(c: mum, gender: CreatureGender.female),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One parent as a CARD: gender, name, and under it the level and the power
/// (user 2026-07-27: "Bitte noch lvl und Energie der Parents anzeigen") — the
/// two figures that say how good a breeder it is, in the same ⚡ the eggs and
/// the monster tiles use.
///
/// THE CARD OPENS IT (user 2026-07-27: "wenn ich auf den namen Drücke, will ich
/// auf das entsprechende Monster kommen im detail screen"). A plain push, so
/// backing out lands on the page you came from with the egg still in its slot.
///
/// The whole card takes the tap, not just the name — and the chevron says so
/// outright, which on parchment an accent colour alone cannot: everything on
/// these pages is brown.
class _ParentCard extends StatelessWidget {
  final CreatureInstance? c;
  final CreatureGender gender;

  const _ParentCard({required this.c, required this.gender});

  @override
  Widget build(BuildContext context) {
    final box = BoxDecoration(
      color: _kCardFill,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: kParchmentInk.withValues(alpha: 0.15)),
    );
    final creature = c;

    if (creature == null) {
      // Released, or from a save this account no longer holds.
      return Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: box,
        child: Row(
          children: [
            Text(
              gender.symbol,
              style: FoE.label(size: 13).copyWith(color: _kInkFaint),
            ),
            const SizedBox(width: 6),
            Text('gone', style: FoE.dim(size: 11).copyWith(color: _kInkFaint)),
          ],
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CreatureDetailScreen(creatureId: creature.id),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
        decoration: box,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        gender.symbol,
                        style: FoE.label(size: 13).copyWith(color: gender.color),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          creature.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FoE.label(
                            size: 12,
                          ).copyWith(color: kParchmentInk),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Lv ${creature.level}   ⚡ ${totalPower(creature)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FoE.dim(size: 10).copyWith(color: _kInkSoft),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: _kAccent),
          ],
        ),
      ),
    );
  }
}

/// THE VALUES OF ONE EGG (user 2026-07-27: "ich muss die Werte eines
/// Ausgewählten eis sehen").
///
/// The breeding screen's gene table with one column instead of two: the child
/// was rolled and FROZEN when the egg was laid (migration 0027), so these are
/// facts about this egg, not a forecast — which is the whole reason it is worth
/// choosing between two eggs of the same species.
///
/// Both genes per stat, as over there: the level-1 value and the growth per
/// level are inherited separately, so showing only the first hides half of what
/// hatched.
class EggGeneTable extends StatefulWidget {
  final BreedingJob job;

  const EggGeneTable({super.key, required this.job});

  @override
  State<EggGeneTable> createState() => _EggGeneTableState();
}

class _EggGeneTableState extends State<EggGeneTable> {
  /// Which gene the bars are drawn from — see [GeneBarToggle].
  bool _showGrowth = false;

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    if (!job.hasChildGenes) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _kAccent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'This egg was laid before its child was frozen onto it — its stats '
          'are rolled when it hatches.',
          style: FoE.dim(size: 11).copyWith(color: kParchmentInk),
        ),
      );
    }

    // BARS, as on the monster detail screen (user 2026-07-27: "gib mir hier die
    // Balken wie beim monster detailscreen") — same row shape and same column
    // widths: label · bar · value · growth.
    //
    // A column of bare numbers made you compare fourteen figures by reading
    // them; the bar answers "what is this one GOOD at?" before you read
    // anything.
    //
    // Scaled to this egg's own biggest gene, exactly like over there: the bars
    // rank the child's stats against each other, they are not a percentage of
    // some cap.
    final bar = kSpeciesDefs[job.speciesId]?.element.color ?? _kAccent;
    // WHICH GENE THE BARS DRAW (user 2026-07-27) — the captions are a switch,
    // see [GeneBarToggle]. The scale follows the same choice, or a growth of +3
    // would be a hairline against a base of 80.
    final genes = _showGrowth ? job.childSlope : job.childBase;
    final maxVal = CreatureStat.values.fold<double>(
      0,
      (m, s) => math.max(m, genes[s] ?? 0),
    );

    Widget row(CreatureStat stat) {
      final v = job.childBase[stat] ?? 0;
      final g = job.childSlope[stat] ?? 0;
      final barValue = genes[stat] ?? 0;
      return Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(
          children: [
            SizedBox(
              width: 86,
              child: Text(
                stat.label,
                style: FoE.dim(size: 11).copyWith(color: _kInkSoft),
              ),
            ),
            Expanded(
              child: RecessBar(
                value: maxVal > 0 ? barValue / maxVal : 0,
                color: bar,
                height: 10,
              ),
            ),
            // VALUE FIRST, then growth (user 2026-07-27: "lvl 1 und level up
            // icon sind vertauscht") — the two number columns ran the other way
            // round to the switch above them and to the breeding table, so the
            // switch's halves sat over the wrong columns.
            SizedBox(
              width: 32,
              child: Text(
                '${v.round()}',
                textAlign: TextAlign.right,
                style: FoE.value(size: 12).copyWith(color: kParchmentInk),
              ),
            ),
            SizedBox(
              width: 42,
              child: Text(
                '+${g.toStringAsFixed(1)}',
                textAlign: TextAlign.right,
                style: FoE.dim(size: 10).copyWith(color: _kInkFaint),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // The captions ARE the control (user 2026-07-27) — they name the two
        // number columns and pick which one the bars draw.
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              const Spacer(),
              GeneBarToggle(
                showGrowth: _showGrowth,
                onChanged: (v) => setState(() => _showGrowth = v),
                ink: kParchmentInk,
                inkFaint: _kInkFaint,
                accent: _kAccent,
              ),
            ],
          ),
        ),
        for (final stat in CreatureStat.values) row(stat),
      ],
    );
  }
}
