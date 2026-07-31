import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../../core/ui/snack.dart';
import '../common/widgets/parchment_page.dart';
import '../settlement/data/goods_definitions.dart';
import '../settlement/settlement_controller.dart';
import '../settlement/widgets/scroll_paper.dart'
    show
        kParchmentInk,
        kParchmentLight,
        parchmentButton,
        parchmentButtonInk;
import 'models/creature_instance.dart';
import 'services/creatures_controller.dart';
import 'services/healing_cost.dart';
import 'widgets/creature_sprite.dart';
import '../common/widgets/recess_bar.dart';

/// The Healing Hut.
///
/// REBUILT AS A LIST, NOT A STACK OF CARDS (user 2026-07-27: "designe mir den
/// healing screen komplett neu, damit alles sehr übersichtlich wird, da es
/// schnell auch mehr verletzte Monster werden können").
///
/// The first version gave every monster a card: portrait, HP bar, and a
/// full-width button carrying its price and its wait. That reads beautifully
/// for two wounded and falls apart at ten — five screens of scrolling, and the
/// Heal-all button at the very bottom, past every card it makes unnecessary.
///
/// What it is now:
///
///  • A BAND at the top with the three numbers that describe the hut — how many
///    it is treating, how many are in line, how many are still hurt — each
///    against its capacity. That is the whole state before you read a name.
///  • THREE GROUPS, each one card with hairline-separated ROWS rather than a
///    card per monster: ~52 px a row instead of ~150. A coloured stripe down the
///    left edge says which group you are in without a heavy heading.
///  • Every row carries the same shape — portrait, name, HP, one figure on the
///    right, one compact action — so a list of twelve is scanned, not read.
///
/// The rules behind it are unchanged: the hut treats [SettlementController.
/// healCapacity] at once, the rest stand in a line capped by `healQueue`, and
/// each pays its own bill the moment its treatment actually starts.
class HealingHutScreen extends StatefulWidget {
  const HealingHutScreen({super.key});

  @override
  State<HealingHutScreen> createState() => _HealingHutScreenState();
}

/// What a row is about — it decides the stripe, the right-hand figure and the
/// action. One enum instead of three near-identical row builders.
enum _Row { treating, queued, wounded }

class _HealingHutScreenState extends State<HealingHutScreen> {
  // The same ink-on-parchment every building page wears.
  static const Color _ink = kParchmentInk;
  static final Color _inkSoft = kParchmentInk.withValues(alpha: 0.78);
  static final Color _inkFaint = kParchmentInk.withValues(alpha: 0.55);
  static const Color _accent = FoE.gold;
  static final Color _cardFill = kParchmentInk.withValues(alpha: 0.06);
  static final Color _hairline = kParchmentInk.withValues(alpha: 0.13);

  final _creatures = CreaturesController();
  final _ctrl = SettlementController();
  Timer? _ticker;

  /// The row whose action is in flight, or null.
  String? _busy;

  @override
  void initState() {
    super.initState();
    // Live countdowns; it also finishes a treatment that ran out while you were
    // standing here, pulls the next one in, and trims a line standing beyond
    // its capacity — so the page ticks whenever EITHER list has anybody in it.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_creatures.healingCreatures.isEmpty && _creatures.healQueue.isEmpty) {
        return;
      }
      _creatures.resolveFinishedHeals();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  List<CreatureInstance> get _inTreatment => _creatures.healingCreatures;

  /// Who is standing in line, in line order (migration 0029).
  List<CreatureInstance> get _queued => _creatures.healQueue;

  /// The wounded who are neither being treated nor queued, worst off first —
  /// the order the hut itself uses when a cap forces the choice, so the list
  /// reads top-down as "who needs it most".
  List<CreatureInstance> get _waiting {
    final list = _creatures.hurtCreatures
        .where((c) => !c.isHealing && !c.isQueuedForHealing)
        .toList();
    list.sort((a, b) {
      if (a.isKo != b.isKo) return a.isKo ? -1 : 1;
      return (b.maxHp - b.hp).compareTo(a.maxHp - a.hp);
    });
    return list;
  }

  /// What treating [c] alone costs, in the goods its own era is billed in.
  Map<String, double> _costOf(CreatureInstance c) => healCost(
    [c],
    _ctrl.resources?.asMap ?? const {},
    costMult: 1 - _ctrl.healReduction('cost'),
  );

  /// How long [c] will be out — the base wound time cut by the hut's healers.
  Duration _durationOf(CreatureInstance c) =>
      healDuration(c) * (1 - _ctrl.healReduction('speed'));

  /// Free treatment slots, or null when the hut has no cap authored.
  int? get _freeSlots {
    final cap = _ctrl.healCapacity;
    return cap == null ? null : cap - _inTreatment.length;
  }

  /// Free places in the line, or null when the waiting room is uncapped.
  int? get _freeQueue => _creatures.freeHealQueueSlots;

  static String _goodsLabel(Map<String, double> cost) => cost.entries
      .map((e) => '${kGoodsDefs[e.key]?.emoji ?? e.key} ${e.value.toInt()}')
      .join(' ');

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  Future<void> _run(String key, Future<String?> Function() action) async {
    setState(() => _busy = key);
    final err = await action();
    if (!mounted) return;
    setState(() => _busy = null);
    if (err != null) context.snack(err, error: true);
  }

  // ── The page ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_creatures, _ctrl]),
    builder: (context, _) => ParchmentPage(
      title: 'Healing Hut',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(ParchmentPage.kParchmentPagePad, 12, ParchmentPage.kParchmentPagePad, 24),
        children: _body(),
      ),
    ),
  );

  List<Widget> _body() {
    final treating = _inTreatment;
    final queued = _queued;
    final waiting = _waiting;

    if (treating.isEmpty && queued.isEmpty && waiting.isEmpty) {
      return [const SizedBox(height: 60), _allWell()];
    }

    return [
      _stateBand(treating.length, queued.length, waiting.length),
      const SizedBox(height: 16),
      if (treating.isNotEmpty) ...[
        _group(
          title: 'In treatment',
          stripe: FoE.positive,
          rows: [for (final c in treating) _row(c, _Row.treating)],
        ),
        const SizedBox(height: 14),
      ],
      if (queued.isNotEmpty) ...[
        _group(
          title: 'In line',
          stripe: _accent,
          note: 'They go in as slots free, in this order — and pay only when '
              'their treatment starts.',
          rows: [
            for (var i = 0; i < queued.length; i++)
              _row(queued[i], _Row.queued, place: i + 1),
          ],
        ),
        const SizedBox(height: 14),
      ],
      if (waiting.isNotEmpty)
        _group(
          title: 'Wounded',
          stripe: FoE.danger,
          // HEAL ALL SITS AT THE TOP, right under the heading (user
          // 2026-07-27: "und oben stehen direkt unter wounded"). It was under
          // the list, which meant scrolling past every card to reach the one
          // button that makes reading them unnecessary.
          leading: _healAllButton(waiting),
          rows: [for (final c in waiting) _row(c, _Row.wounded)],
        )
      else if (queued.isNotEmpty || treating.isNotEmpty)
        Text(
          'Everyone hurt is in the hut or in line.',
          style: FoE.dim(size: 12).copyWith(color: _inkFaint),
        ),
    ];
  }

  Widget _allWell() => Column(
    children: [
      Text('❤', style: TextStyle(fontSize: 30, color: FoE.positive)),
      const SizedBox(height: 10),
      Text(
        'Everyone is at full health.',
        textAlign: TextAlign.center,
        style: FoE.label(size: 13).copyWith(color: _inkSoft),
      ),
      const SizedBox(height: 4),
      Text(
        'Wounded monsters turn up here after a fight.',
        textAlign: TextAlign.center,
        style: FoE.dim(size: 11).copyWith(color: _inkFaint),
      ),
    ],
  );

  /// THE HUT AT A GLANCE — the three numbers that describe it, each against its
  /// capacity where one is authored. Answers "can I send anyone in right now?"
  /// before a single name is read, which with a dozen wounded is the whole
  /// difference between a list and a wall.
  Widget _stateBand(int treating, int queued, int wounded) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    decoration: ShapeDecoration(color: _cardFill, shape: FoE.facet(radius: 12, side: BorderSide(color: kParchmentInk.withValues(alpha: 0.15)))),
    child: Row(
      children: [
        _bandFact('🩹', treating, _ctrl.healCapacity, 'treating', FoE.positive),
        _bandDivider(),
        _bandFact('⏳', queued, _ctrl.healQueueCapacity, 'in line', _accent),
        _bandDivider(),
        _bandFact('💔', wounded, null, 'wounded', FoE.danger),
      ],
    ),
  );

  Widget _bandFact(String glyph, int n, int? cap, String label, Color tint) =>
      Expanded(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(glyph, style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 5),
                Text(
                  // Never a fraction that reads as impossible: the controller
                  // trims an over-full line on the next resolve, and this is
                  // the frame in between.
                  cap == null ? '$n' : '$n/${cap < n ? n : cap}',
                  style: FoE.value(size: 15).copyWith(color: tint),
                ),
              ],
            ),
            const SizedBox(height: 1),
            Text(label, style: FoE.dim(size: 9).copyWith(color: _inkFaint)),
          ],
        ),
      );

  Widget _bandDivider() => Container(width: 1, height: 26, color: _hairline);

  /// One group: a heading, an optional note and leading action, then the rows
  /// as ONE card with hairlines between them.
  ///
  /// A card per monster made every list three times taller than it needed to
  /// be and gave twelve identical frames equal weight. A single framed list
  /// with a coloured left stripe reads as one thing you scan.
  Widget _group({
    required String title,
    required Color stripe,
    required List<Widget> rows,
    String? note,
    Widget? leading,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Container(width: 3, height: 13, color: stripe),
          const SizedBox(width: 7),
          Text(
            title.toUpperCase(),
            style: FoE.dim(size: 10).copyWith(
              color: _inkSoft,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${rows.length}',
            style: FoE.value(size: 11).copyWith(color: _inkFaint),
          ),
        ],
      ),
      if (note != null) ...[
        const SizedBox(height: 4),
        Text(note, style: FoE.dim(size: 10).copyWith(color: _inkFaint)),
      ],
      const SizedBox(height: 7),
      if (leading != null) ...[leading, const SizedBox(height: 8)],
      Container(
        clipBehavior: Clip.antiAlias,
        decoration: ShapeDecoration(color: _cardFill, shape: FoE.facet(radius: 12, side: BorderSide(color: kParchmentInk.withValues(alpha: 0.15)))),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Container(height: 1, color: _hairline),
              rows[i],
            ],
          ],
        ),
      ),
    ],
  );

  /// ONE MONSTER, ONE ROW — the same shape in all three groups: portrait, name
  /// with its HP under it, one figure on the right, one compact action.
  ///
  /// [place] is the queue position, shown only in the line.
  Widget _row(CreatureInstance c, _Row kind, {int? place}) {
    final hpFrac = c.maxHp <= 0 ? 0.0 : (c.hp / c.maxHp).clamp(0.0, 1.0);
    final hpColor = hpFrac < 0.3 ? FoE.danger : FoE.positive;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        children: [
          if (place != null)
            SizedBox(
              width: 16,
              child: Text(
                '$place',
                style: FoE.value(size: 11).copyWith(color: _inkFaint),
              ),
            ),
          _portrait(c),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        c.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FoE.label(size: 12).copyWith(color: _ink),
                      ),
                    ),
                    if (c.isKo) ...[
                      const SizedBox(width: 5),
                      Text(
                        'K.O.',
                        style: FoE.value(size: 9).copyWith(color: FoE.danger),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: RecessBar(
                        value: hpFrac,
                        color: hpColor,
                        height: 9,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${c.hp}/${c.maxHp}',
                      style: FoE.dim(size: 9).copyWith(color: _inkFaint),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _rowTrailing(c, kind),
        ],
      ),
    );
  }

  /// The right-hand end of a row: what this monster is waiting on, and the one
  /// thing you can do about it.
  Widget _rowTrailing(CreatureInstance c, _Row kind) {
    switch (kind) {
      case _Row.treating:
        final skip = _creatures.healSkipCost(c);
        final key = 'skip_${c.id}';
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _fmt(c.healingRemaining),
              style: FoE.value(size: 12).copyWith(color: FoE.positive),
            ),
            if (skip > 0) ...[
              const SizedBox(width: 8),
              // Finish it now for gold — the same buy-out the build queue and
              // the Hatchery offer, priced on the REAL time left.
              _pill(
                '🪙 $skip',
                _accent,
                _busy == key || _ctrl.gold < skip
                    ? null
                    : () => _run(key, () => _creatures.skipHealWithGold(c)),
              ),
            ],
          ],
        );

      case _Row.queued:
        final key = 'unqueue_${c.id}';
        return _pill(
          'Leave',
          _inkFaint,
          _busy == key
              ? null
              : () async {
                  setState(() => _busy = key);
                  await _creatures.unqueueHealing(c);
                  if (mounted) setState(() => _busy = null);
                },
        );

      case _Row.wounded:
        final key = 'heal_${c.id}';
        final cost = _costOf(c);
        final affordable = canAfford(cost, _ctrl.resources?.asMap ?? const {});
        final slots = _freeSlots;
        // FULL IS NOT A REFUSAL — it means "join the line". The bill is only
        // checked for a treatment that starts NOW; a queued monster pays when
        // its slot comes up, so a bare purse must not stop it getting in line.
        final queueing = slots != null && slots <= 0;
        final lineFull = queueing && (_freeQueue ?? 1) <= 0;
        final live = _busy == null && !lineFull && (queueing || affordable);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // What it costs and how long it takes, on the ROW rather than on
            // the button: with a dozen of them the figures line up into a
            // column you can compare straight down.
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _goodsLabel(cost),
                  style: FoE.value(size: 11).copyWith(
                    color: affordable ? _ink : FoE.danger,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '⏱ ${_fmt(_durationOf(c))}',
                  style: FoE.dim(size: 9).copyWith(color: _inkFaint),
                ),
              ],
            ),
            const SizedBox(width: 8),
            _pill(
              lineFull
                  ? 'Full'
                  : queueing
                      ? 'Line up'
                      : 'Treat',
              live ? FoE.positive : _inkFaint,
              live ? () => _run(key, () => _creatures.queueForHealing(c)) : null,
              filled: live,
            ),
          ],
        );
    }
  }

  /// Everyone still wounded, in one move — the shortcut for the case the hut
  /// exists for: you just lost a fight and the whole party is bleeding.
  ///
  /// "HEAL ALL" whatever the hut can take right now (user 2026-07-27: "das soll
  /// heal all sein"). It was three different verbs for one button, so the one
  /// control that always does the same thing looked like three; what CHANGES
  /// with the room available belongs after the name.
  Widget _healAllButton(List<CreatureInstance> waiting) {
    final cost = _creatures.healAllCost;
    final slots = _freeSlots;
    final queueing = slots != null && slots < waiting.length;
    // How many the hut can actually take right now: its free slots plus the
    // free places in the line. Null on either side means unlimited there.
    final room = slots == null || _freeQueue == null
        ? waiting.length
        : slots + _freeQueue!;
    final takes = room < waiting.length ? room : waiting.length;
    final live = _busy == null && takes > 0;
    return GestureDetector(
      onTap: live ? () => _run('all', _creatures.healAll) : null,
      child: Opacity(
        opacity: live ? 1 : 0.55,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: parchmentButton(active: live),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Heal all ${waiting.length}',
                style: FoE.label(
                  size: 13,
                ).copyWith(color: parchmentButtonInk(active: live)),
              ),
              const SizedBox(height: 2),
              Text(
                takes <= 0
                    ? 'No room — treat somebody first'
                    : takes < waiting.length
                        ? 'only $takes fit for now, the rest stay here'
                        : queueing
                            ? '${_goodsLabel(cost)} · some will wait their turn'
                            : _goodsLabel(cost),
                textAlign: TextAlign.center,
                style: FoE.dim(size: 10).copyWith(
                  color: parchmentButtonInk(active: live),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _portrait(CreatureInstance c) => SizedBox(
    width: 34,
    height: 34,
    child: c.imageUrl == null
        ? Icon(Icons.pets, size: 20, color: _accent)
        : CreatureSprite(
            url: c.imageUrl!,
            fallback: Icon(Icons.pets, size: 20, color: _accent),
          ),
  );

  /// The one compact control shape every row uses: 28 px tall, tinted in its
  /// own colour, filled when it is the row's live commit.
  Widget _pill(
    String label,
    Color color,
    VoidCallback? onTap, {
    bool filled = false,
  }) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: ShapeDecoration(color: color.withValues(alpha: filled ? 0.9 : 0.07), shape: FoE.facet(radius: 9, side: BorderSide(color: color.withValues(alpha: filled ? 0.9 : 0.5)))),
        child: Text(
          label,
          style: FoE.label(size: 11).copyWith(
            color: filled ? kParchmentLight : color,
          ),
        ),
      ),
    ),
  );
}
