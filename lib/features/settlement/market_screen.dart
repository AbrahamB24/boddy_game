import 'data/resource_icons.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../../core/ui/snack.dart';
import '../common/widgets/filter_pills.dart';
import '../common/widgets/parchment_page.dart';
import '../creatures/models/creature_instance.dart';
import '../creatures/models/expedition.dart';
import '../creatures/models/saved_team.dart';
import '../creatures/services/creatures_controller.dart';
import '../creatures/services/expedition_controller.dart';
import '../creatures/widgets/creature_card.dart';
import 'caravan_picker_screen.dart';
import 'data/goods_definitions.dart';
import 'data/item_definitions.dart';
import 'services/gold_economy.dart';
import 'services/trade_caravan.dart';
import 'services/trade_center.dart';
import 'settlement_controller.dart';
import 'widgets/scroll_paper.dart' show kPageShadow, kParchmentInk, kParchmentLight;
import '../common/widgets/recess_bar.dart';

/// The Market — A SCREEN OF ITS OWN, ON THE HATCHERY'S PLAN (user 2026-07-27:
/// "gestalte den Market genau so wie die Hatchery. D.h eigener Screen und
/// gestaltung daran angelehnt").
///
/// It was a `DraggableScrollableSheet` on FoE's dark panels with a Material
/// TabBar — the last building feature that still opened as a popup, and the only
/// one that did not look like the paper the settlement is drawn on. Two problems
/// came with that: the sheet capped itself at 72 % of the window while carrying
/// three tabs of rows, and only the Sell tab held the drag controller, so the
/// other two felt stuck (there was an explicit ✕ to work around it — now the
/// route's own back button).
///
/// SAME TWO HALVES, SAME ORDER as the Hatchery and the Breeding Hut: what is
/// RUNNING on top with its live countdowns, and the thing you came to DO
/// underneath — a slot you fill (there an egg, here the caravan), the values of
/// what you picked laid out under it, and ONE button carrying the price.
///
/// Every rate still comes from services/trade_center.dart with the building's
/// [SettlementController.tradeDiscount] applied, so nothing here invents a
/// price, and the spread stays visible in the card that charges it.
///
/// **Goods travel** (user 2026-07-26). Sell, barter and buy-with-gold each load
/// a CARAVAN and send it out as an expedition, which is why the caravan is the
/// slot this page is built around — with none loaded there is no trade, exactly
/// as there is no incubation without an egg. The Shop stays instant: an item you
/// buy for the fight you are in right now is worth nothing in two hours.
class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

/// The three trades, as a segmented control rather than a [TabBar] — the
/// parchment pages have no Material chrome on them anywhere else.
enum _MarketTab {
  sell('Sell'),
  shop('Shop'),
  exchange('Exchange');

  final String label;
  const _MarketTab(this.label);
}

class _MarketScreenState extends State<MarketScreen> {
  // The same ink-on-parchment the Hatchery, the breeding page and the building
  // dialog wear.
  static const Color _ink = kParchmentInk;
  static final Color _inkSoft = kParchmentInk.withValues(alpha: 0.78);
  static final Color _inkFaint = kParchmentInk.withValues(alpha: 0.55);
  static const Color _accent = FoE.gold;
  static final Color _cardFill = kParchmentInk.withValues(alpha: 0.06);

  /// This page is parchment, so its pills are.
  static final PillPalette _pills = PillPalette.parchment;

  final _ctrl = SettlementController();
  final _exp = ExpeditionController();
  final _creatures = CreaturesController();
  Timer? _ticker;

  /// The key of the card whose send is in flight, or null.
  String? _busy;

  _MarketTab _tab = _MarketTab.sell;

  /// The creatures loaded onto the next caravan. Empty until you pick one —
  /// every goods trade is gated on it, which is the point: a trade is a trip,
  /// and a trip needs somebody to make it.
  final List<CreatureInstance> _caravan = [];

  /// Exchange tab: what you give and what you want.
  String _from = 'wood';
  String _to = 'fish';

  /// How much each card is set to trade, by card key — IN UNITS, not as a
  /// fraction (user 2026-07-27: "mache einen slider und nicht in prozent
  /// sondern in effektiven zahlen"). Unset means "the whole load": the caravan's
  /// capacity is the real limit, and an untouched slider should offer all of it.
  ///
  /// Kept as the RAW value and clamped on read, so swapping to a smaller
  /// caravan pulls the offer down without forgetting what you had asked for.
  final Map<String, double> _amount = {};

  @override
  void initState() {
    super.initState();
    // Drop anyone who became unavailable (sent out, K.O.) while the page sat
    // open — the send would only bounce off startTrade's own check.
    _exp.addListener(_pruneCaravan);
    _creatures.addListener(_pruneCaravan);
    // Live countdowns, and it pays out a caravan that lands while you are
    // standing here — the same tick the Hatchery runs over its eggs.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _trips.isEmpty) return;
      if (_exp.expeditions.any((e) => e.isReadyToCollect(DateTime.now()))) {
        _exp.collectFinished();
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _exp.removeListener(_pruneCaravan);
    _creatures.removeListener(_pruneCaravan);
    super.dispose();
  }

  void _pruneCaravan() {
    if (!mounted) return;
    final ready = _creatures.availableForExpedition().map((c) => c.id).toSet();
    setState(() => _caravan.removeWhere((c) => !ready.contains(c.id)));
  }

  /// The caravans on the road — this page's "Incubating".
  List<Expedition> get _trips => [
    for (final e in _exp.expeditions)
      if (e.type == ExpeditionType.trade) e,
  ];

  // ── Sending ───────────────────────────────────────────────────────────
  Future<void> _run(String key, Future<String?> Function() action) async {
    setState(() => _busy = key);
    final err = await action();
    if (!mounted) return;
    setState(() => _busy = null);
    if (err != null) context.snack(err, error: true);
  }

  /// Sends [amountFrom] of [from] out and books [amountTo] of [to] for the
  /// return. Every goods trade on this page goes through here, so the cargo
  /// rules and the capacity check can't differ between the three tabs.
  Future<String?> _send({
    required String from,
    required double amountFrom,
    required String to,
    required double amountTo,
  }) => _exp.startTrade(
    members: _caravan,
    from: from,
    amountFrom: amountFrom,
    to: to,
    amountTo: amountTo,
  );

  /// How much of [resource] this caravan may take on, ignoring stock. 0 with no
  /// caravan, which is what disables every send button.
  double _capacity(String resource) => _caravan.isEmpty
      ? 0
      : tradeCapacity(
          resource,
          _caravan,
          carryMult: _ctrl.caravanBonuses.carryMult,
        );

  /// The most of [resource] a caravan can take given the [stock] on hand — the
  /// number every offer below sizes itself against.
  double _haulable(String resource, double stock) => _caravan.isEmpty
      ? 0
      : maxTradeAmount(
          resource,
          _caravan,
          stock,
          carryMult: _ctrl.caravanBonuses.carryMult,
        );

  Duration get _tripTime => tradeTripDuration(
    _caravan,
    travelMult: _ctrl.caravanBonuses.travelMult,
  );

  static String _fmtTrip(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    final h = d.inMinutes ~/ 60;
    final m = d.inMinutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m ${s}s';
  }

  // ── The page ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_ctrl, _exp, _creatures]),
    builder: (context, _) => ParchmentPage(
      title: 'Market',
      // The purse, where the Hatchery keeps its slot count — every price below
      // is in gold, so the balance belongs on screen at all times rather than
      // scrolling away with the Shop.
      trailing: Text(
        '🪙 ${_ctrl.gold.toInt()}',
        style: FoE.value(size: 13).copyWith(color: _accent),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(ParchmentPage.kParchmentPagePad, 12, ParchmentPage.kParchmentPagePad, 20),
        children: [
          // RUNNING FIRST, as on the Hatchery.
          ..._tripSection(),
          const SizedBox(height: 18),
          Text('New trade', style: FoE.title(size: 13).copyWith(color: _ink)),
          const SizedBox(height: 8),
          _caravanPanel(),
          const SizedBox(height: 16),
          _tabBar(),
          const SizedBox(height: 14),
          ..._tabBody(),
          const SizedBox(height: 20),
        ],
      ),
    ),
  );

  // ── The running half: caravans on the road ────────────────────────────

  /// The Hatchery's "Incubating" section, over trade expeditions: a titled group
  /// with its cards and the slot count on the right, or a dim placeholder line.
  List<Widget> _tripSection() {
    final trips = _trips;
    return [
      Row(
        children: [
          Text(
            'On the road',
            style: FoE.title(size: 13).copyWith(color: _ink),
          ),
          const Spacer(),
          // THE CARAVAN POOL, which is the market's own (user 2026-07-29:
          // "unterscheide expeditions und karawanen für den Markt"). It used
          // to show the expedition slots, because a trade run took one — so
          // sending wood to market cost you a hunt. The two pools are separate
          // now; the Caravanserai fills this one.
          Text(
            '🐫 ${_exp.caravanCount}/${_exp.maxCaravanSlots}',
            style: FoE.value(size: 12).copyWith(
              color: _exp.caravansFull ? FoE.danger : _accent,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (trips.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'No caravan out.',
            style: FoE.dim(size: 12).copyWith(color: _inkFaint),
          ),
        )
      else
        for (final e in trips) _tripCard(e),
      const SizedBox(height: 14),
    ];
  }

  /// One caravan on the road — the Hatchery's incubation card, to the value:
  /// the cargo's glyph, what it will bring home, the countdown, and a PROGRESS
  /// BAR that answers the question a countdown alone leaves open (nearly there,
  /// or barely gone?).
  ///
  /// No action on it. A trade pays itself out the moment it lands (the ticker
  /// above collects it), so a button here would be a button for nothing — where
  /// the Hatchery's egg genuinely waits for you to hatch it.
  Widget _tripCard(Expedition e) {
    final now = DateTime.now();
    final from = e.payload['from'] as String? ?? '';
    final to = e.payload['to'] as String? ?? '';
    final amountFrom = (e.payload['amountFrom'] as num?)?.toDouble() ?? 0;
    final amountTo = (e.payload['amountTo'] as num?)?.toDouble() ?? 0;
    final ready = e.isReadyToCollect(now);
    final frac = e.progress(now);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: ready ? _accent.withValues(alpha: 0.12) : _cardFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ready ? _accent : kParchmentInk.withValues(alpha: 0.18),
          width: ready ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          // WHAT IS COMING HOME, not the pack animal: the return leg is the
          // reason the trip was sent, and it is what you are waiting for.
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Text(_emoji(to), style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${amountFrom.toInt()} ${_name(from)}  →  '
                        '${amountTo.toInt()} ${_name(to)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FoE.label(size: 13).copyWith(color: _ink),
                      ),
                    ),
                    if (!ready)
                      Text(
                        _fmt(e.remaining(now)),
                        style: FoE.value(size: 12).copyWith(color: _inkSoft),
                      ),
                  ],
                ),
                const SizedBox(height: 7),
                RecessBar(
                  value: frac,
                  color: ExpeditionType.trade.color,
                  height: 10,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── The doing half: the caravan slot ──────────────────────────────────

  /// ONE PLACE PER SEAT THE CARAVAN HAS (user 2026-07-27: "ich möchte oben
  /// jeweils ein + im gleichen Stile wie jetzt haben, für jeden Platz, welche
  /// die Karawane aktuell hat, so dass ich die Monster einzeln hinzufügen
  /// kann").
  ///
  /// It was ONE slot that opened a multi-select grid: to change a single hauler
  /// you rebuilt the whole party, and nothing on the page said how many places
  /// the caravan even had. Now the places are the picture — [teamSizeCap] of
  /// them, each a `+` you fill on its own, so the row answers "how big is my
  /// caravan and how much of it is loaded" at a glance.
  Widget _caravanPanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _caravanHeader(),
      const SizedBox(height: 8),
      _caravanRank(),
      if (_caravan.isNotEmpty) ...[
        const SizedBox(height: 12),
        _caravanFacts(),
      ],
      ..._savedCaravans(),
    ],
  );

  Widget _caravanHeader() => Row(
    children: [
      Text(
        'CARAVAN',
        style: FoE.dim(size: 9).copyWith(
          color: _inkFaint,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
      const SizedBox(width: 8),
      Text(
        '${_caravan.length}/${_creatures.teamSizeCap}',
        style: FoE.value(size: 11).copyWith(color: _accent),
      ),
      const Spacer(),
      if (_caravan.isNotEmpty)
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(_caravan.clear),
          child: Text(
            'Clear',
            style: FoE.label(size: 11).copyWith(color: _inkFaint),
          ),
        ),
    ],
  );

  /// The places, as MONSTER TILES (user 2026-07-27: "übernimm bitte überall
  /// genau diese Kachel für die Monster, wo diese benutzt wird. Bsp. beim Markt
  /// für die Karawane. Diese sieht aktuell noch nicht genau gleich aus,
  /// besonders die Grösse").
  ///
  /// They were bespoke: a sprite on a flat pedestal, sized by a fixed height so
  /// six would fit in one row. That made a hauler look like a different kind of
  /// object here than it does in the Monsters grid, the breeding slots or the
  /// picker one tap away — and the picker is the one place you compare the two.
  ///
  /// So it is [CreatureCard] now, in the Monsters grid's own cell: three across
  /// at aspect 0.70, wrapping to a second row when the caravan grows past three
  /// places. Same tile, same size, everywhere.
  Widget _caravanRank() {
    final cap = _creatures.teamSizeCap;
    // THE MONSTERS GRID'S OWN DELEGATE (user 2026-07-27: "mache diese genau
    // gleich gross/hoch wie beim Monsterscreen"). Same count, same spacing,
    // same aspect, and the page now carries the same side padding — so the
    // cells work out to the same pixels rather than merely the same shape.
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: _kTileAspect,
      ),
      itemCount: cap,
      itemBuilder: (_, i) =>
          i < _caravan.length ? _memberCard(_caravan[i], i) : _emptySlot(i),
    );
  }

  /// The Monsters-grid cell shape, which every monster tile in the game is
  /// drawn in — the Hatchery's egg slot and the breeding parents included.
  static const double _kTileAspect = 0.70;

  /// An unfilled place, in the BUILD MENU'S dead-card style — the same frame the
  /// Hatchery's egg slot and the breeding screen's parent slots wear, so an
  /// empty place lines up with the tile that will fill it. A tap fills THIS
  /// place, and only this one.
  Widget _emptySlot(int index) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: _addHauler,
    child: LayoutBuilder(
      // The tile reserves its top 17 % for the art that pops out of it; the
      // empty card leaves the same gap so the row lines up.
      builder: (context, box) => Padding(
        padding: EdgeInsets.only(top: box.maxHeight * 0.17),
        child: Container(
          decoration: BoxDecoration(
            color: kParchmentInk.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: kPageShadow.withValues(alpha: 0.24),
                blurRadius: 0,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_circle_outline, size: 24, color: _inkFaint),
              // Only the NEXT place to be filled says what a tap does — six
              // copies of "Add" is noise, and one is a caption for the rank.
              if (index == _caravan.length) ...[
                const SizedBox(height: 5),
                Text(
                  'Add',
                  style: FoE.label(size: 11).copyWith(color: _inkFaint),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  /// One filled place: THE monster tile, unchanged from every other screen.
  ///
  /// A TAP TAKES IT BACK OUT, and the ✕ badge says so. Emptying a place is the
  /// exact inverse of filling it, so it is the same single tap on the same
  /// place — no picker, no rebuilding the party to drop one member.
  Widget _memberCard(CreatureInstance c, int index) => GestureDetector(
    // The tap lives on the WHOLE place, not on the tile inside it: the ✕ sits
    // in the band the tile leaves empty for its artwork, so a tap aimed at the
    // badge has to be caught out here.
    behavior: HitTestBehavior.opaque,
    onTap: () => setState(() => _caravan.removeAt(index)),
    child: Stack(
      children: [
        Positioned.fill(child: CreatureCard(creature: c)),
        Positioned(
          top: 0,
          right: 0,
          child: Icon(
            Icons.cancel,
            size: 18,
            color: kParchmentInk.withValues(alpha: 0.7),
          ),
        ),
      ],
    ),
  );

  // ── Saved caravans (user 2026-07-27) ──────────────────────────────────
  // "Zudem muss ich caravanen speichern können und schnellladen aus diesem
  // menü heraus."
  //
  // Picking haulers is the slowest step of a trade and the one you repeat
  // unchanged: the same two carriers go out every time, and rebuilding that
  // party through the picker on every visit is the whole friction. A saved
  // caravan is the same object a saved BATTLE TEAM is — a name and a list of
  // ids — so it is stored in the same table under a `kind` (migration 0028)
  // rather than in a second one of its own.
  //
  // The strip shows WITH THE SLOT EMPTY too: quick-loading is the reason it
  // exists, and hiding it until a caravan is loaded would put it behind the
  // work it saves you.

  List<Widget> _savedCaravans() {
    final saved = _creatures.caravans;
    final canSave = _caravan.isNotEmpty && _matchingSaved() == null;
    if (saved.isEmpty && !canSave) return const [];
    return [
      const SizedBox(height: 12),
      Row(
        children: [
          Text(
            'SAVED CARAVANS',
            style: FoE.dim(size: 9).copyWith(
              color: _inkFaint,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          if (canSave)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _saveCaravan,
              child: Text(
                'Save this one',
                style: FoE.label(size: 11).copyWith(color: _accent),
              ),
            ),
        ],
      ),
      const SizedBox(height: 6),
      if (saved.isEmpty)
        Text(
          'Save the party you just built and it lands here — one tap to send '
          'the same haulers again.',
          style: FoE.dim(size: 10).copyWith(color: _inkFaint),
        )
      else
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final t in saved) _savedPill(t)],
        ),
    ];
  }

  /// The saved caravan whose members are exactly the loaded ones, or null.
  /// Order does not matter — a caravan is a set of haulers, not a batting
  /// order, so the same three monsters picked in another sequence is the same
  /// caravan and must not offer to be saved twice.
  SavedTeam? _matchingSaved() {
    final mine = {for (final c in _caravan) c.id};
    for (final t in _creatures.caravans) {
      if (t.memberIds.length == mine.length && mine.containsAll(t.memberIds)) {
        return t;
      }
    }
    return null;
  }

  /// One saved caravan: tap to load it, ✕ to forget it. The one currently in
  /// the slot wears the accent, so "which of these am I looking at?" is
  /// answered without opening anything.
  Widget _savedPill(SavedTeam team) {
    final loaded = _matchingSaved()?.id == team.id;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _loadSaved(team),
      child: Container(
        height: 34,
        padding: const EdgeInsets.only(left: 12, right: 6),
        decoration: BoxDecoration(
          color: _accent.withValues(alpha: loaded ? 0.16 : 0.06),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: _accent.withValues(alpha: loaded ? 1 : 0.45),
            width: loaded ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              team.name,
              style: FoE.label(size: 12).copyWith(color: _accent),
            ),
            const SizedBox(width: 6),
            Text(
              '${team.memberIds.length}',
              style: FoE.dim(size: 10).copyWith(color: _inkFaint),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _forgetSaved(team),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Icon(Icons.close, size: 14, color: _inkFaint),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Quick-load: the saved ids, resolved to whoever is actually free right now.
  ///
  /// A roster is INTENT, not a live claim (the same rule battleTeam() follows),
  /// so a member who is K.O. or already out is skipped rather than blocking the
  /// load — but it is said out loud, because a caravan that quietly comes back
  /// two monsters short would just look like a broken button.
  void _loadSaved(SavedTeam team) {
    final free = {
      for (final c in _creatures.availableForExpedition()) c.id: c,
    };
    final members = [
      for (final id in team.memberIds)
        if (free[id] != null) free[id]!,
    ];
    if (members.isEmpty) {
      context.snack('Nobody from "${team.name}" is free to travel.');
      return;
    }
    setState(() {
      _caravan
        ..clear()
        ..addAll(members.take(_creatures.teamSizeCap));
    });
    final missing = team.memberIds.length - members.length;
    if (missing > 0) {
      context.snack(
        '${team.name} loaded — $missing member${missing > 1 ? 's are' : ' is'} '
        'not free right now.',
      );
    }
  }

  Future<void> _saveCaravan() async {
    final controller = TextEditingController(
      text: 'Caravan ${_creatures.caravans.length + 1}',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kParchmentLight,
        title: Text(
          'Save this caravan',
          style: FoE.title(size: 15).copyWith(color: _ink),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: FoE.label(size: 13).copyWith(color: _ink),
          cursorColor: _accent,
          onSubmitted: (v) => Navigator.pop(ctx, v),
          decoration: InputDecoration(
            hintText: 'Name it',
            hintStyle: FoE.dim(size: 12).copyWith(color: _inkFaint),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: _inkFaint),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: _accent),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: FoE.label(size: 12).copyWith(color: _ink),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(
              'Save',
              style: FoE.label(size: 12).copyWith(color: _accent),
            ),
          ),
        ],
      ),
    );
    if (name == null || !mounted) return;
    final err = await _creatures.saveCaravan(
      name,
      [for (final c in _caravan) c.id],
    );
    if (!mounted) return;
    if (err != null) context.snack(err, error: true);
  }

  Future<void> _forgetSaved(SavedTeam team) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kParchmentLight,
        title: Text(
          'Forget "${team.name}"?',
          style: FoE.title(size: 15).copyWith(color: _ink),
        ),
        content: Text(
          'Only the saved party is dropped — the monsters in it are untouched.',
          style: FoE.dim(size: 12).copyWith(color: _inkSoft),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Keep',
              style: FoE.label(size: 12).copyWith(color: _ink),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Forget',
              style: FoE.label(size: 12).copyWith(color: FoE.danger),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _creatures.deleteTeam(team);
  }

  /// The three numbers the caravan decides, stated ONCE. The Hatchery puts its
  /// wait on the Hatch button because the egg carries it; here every trade on
  /// the page rides the same caravan, so repeating the trip time on six buttons
  /// would be the same fact six times.
  Widget _caravanFacts() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: _cardFill,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: kParchmentInk.withValues(alpha: 0.15)),
    ),
    child: Row(
      children: [
        _fact('🏋', '${caravanCarry(_caravan)}', 'carry'),
        _fact('🥾', '${caravanSpeed(_caravan)}', 'speed'),
        _fact('⏱', _fmtTrip(_tripTime), 'round trip'),
      ],
    ),
  );

  Widget _fact(String glyph, String value, String label) => Expanded(
    child: Column(
      children: [
        Text(
          '$glyph $value',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: FoE.value(size: 13).copyWith(color: _ink),
        ),
        const SizedBox(height: 1),
        Text(label, style: FoE.dim(size: 9).copyWith(color: _inkFaint)),
      ],
    ),
  );

  /// Fills ONE place from the picker's single-pick mode. Appends rather than
  /// writing to a fixed index: the places are a rank, not numbered seats, so a
  /// caravan is always the first N of them with no holes in the middle.
  Future<void> _addHauler() async {
    if (_caravan.length >= _creatures.teamSizeCap) return;
    final picked = await Navigator.push<List<CreatureInstance>>(
      context,
      MaterialPageRoute(
        builder: (_) => CaravanPickerScreen(selected: _caravan),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() {
      // Guard against a double-tap racing two routes onto the same place.
      if (_caravan.any((c) => c.id == picked.first.id)) return;
      if (_caravan.length < _creatures.teamSizeCap) _caravan.add(picked.first);
    });
  }

  // ── The three trades ──────────────────────────────────────────────────

  /// The tabs as a SEGMENTED CONTROL, the shape [GeneBarToggle] gave the
  /// parchment pages: a bordered track with the live segment filled. A Material
  /// TabBar's underline indicator is the one piece of chrome none of the other
  /// building pages wear.
  Widget _tabBar() => Container(
    height: 34,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: _inkFaint.withValues(alpha: 0.45)),
    ),
    child: Row(
      children: [
        for (final t in _MarketTab.values)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _tab = t),
              child: Container(
                height: double.infinity,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _tab == t
                      ? _accent.withValues(alpha: 0.16)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Text(
                  t.label,
                  style: FoE.label(size: 12).copyWith(
                    color: _tab == t ? _accent : _inkFaint,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  List<Widget> _tabBody() {
    final res = _ctrl.resources;
    if (res == null) {
      return [
        Text('Loading…', style: FoE.dim(size: 12).copyWith(color: _inkFaint)),
      ];
    }
    final era = _ctrl.settlement?.eraIndex ?? 1;
    final tradeable = tradeableResources(era);
    final discount = _ctrl.tradeDiscount;
    return switch (_tab) {
      _MarketTab.sell => _sellBody(tradeable, res.asMap),
      _MarketTab.shop => _shopBody(discount),
      _MarketTab.exchange => _exchangeBody(tradeable, res.asMap, discount),
    };
  }

  /// The line of prose each tab opens with, plus the Trade Center's own bonus
  /// where it changes the numbers. The bonus is stated rather than silently
  /// applied — every price below moves with it, so hiding it would make them
  /// look arbitrary.
  Widget _intro(String text) {
    final discount = _ctrl.tradeDiscount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: FoE.dim(size: 11).copyWith(color: _inkSoft)),
        if (discount > 0) ...[
          const SizedBox(height: 4),
          Text(
            'Trade Center bonus: ${(discount * 100).round()}% better rates',
            style: FoE.dim(size: 11).copyWith(color: _accent),
          ),
        ],
        const SizedBox(height: 12),
      ],
    );
  }

  // ── Tab 1: surplus → gold ─────────────────────────────────────────────
  List<Widget> _sellBody(List<String> tradeable, Map<String, double> stock) => [
    _intro(
      'Sell what you have spare. The caravan hauls it out and brings the gold '
      'back — 1 🪙 skips about a minute of any wait, and buys items in the Shop.',
    ),
    _tradeList([
      for (final r in tradeable) _sellRow(r, stock[r] ?? 0),
    ]),
  ];

  Widget _sellRow(String resource, double stock) {
    final key = 'sell_$resource';
    // The slider runs to what the CARAVAN can take, not to what the storehouse
    // holds: a slider reaching 8 000 logs that then bounces off the capacity
    // check is a trap.
    final haulable = _haulable(resource, stock);
    final amount = _amountFor(key, haulable);
    final earns = sellValue(resource, amount);
    return _tradeRow(
      resource: resource,
      subtitle: '${stock.toInt()} in store',
      sliderKey: key,
      max: haulable,
      amount: amount,
      result: '🪙 $earns',
      action: 'Sell',
      blocked: _blockedReason(resource, amount, earns > 0),
      onTap: () => _run(
        key,
        () => _send(
          from: resource,
          amountFrom: amount,
          to: 'gold',
          amountTo: earns.toDouble(),
        ),
      ),
    );
  }

  /// A framed list with hairlines between its rows — the Healing Hut's shape,
  /// which the Shop already wears (user 2026-07-27: "sell und exchange sind
  /// noch nicht angepasst. Diese sollen viel kompakter sein").
  Widget _tradeList(List<Widget> rows) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: _cardFill,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: kParchmentInk.withValues(alpha: 0.18)),
    ),
    child: Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0)
            Container(height: 1, color: kParchmentInk.withValues(alpha: 0.13)),
          rows[i],
        ],
      ],
    ),
  );

  /// ONE GOODS TRADE, IN A ROW. Selling and buying-with-gold are the same
  /// shape — a resource, an amount, a price — so they are the same widget.
  ///
  /// Each was a card: a header, a rate line, a capacity note, a slider and a
  /// full-width green button. Six tradeable goods made that nine hundred pixels
  /// of page for what is, per line, three numbers.
  ///
  /// What went, and why it was safe:
  ///  • THE RATE LINE ("3 Wood → 🪙 1"). The row prints what the chosen amount
  ///    actually fetches, which is the figure you act on; the unit rate was the
  ///    long way round to it.
  ///  • THE CAPACITY NOTE ("Caravan holds 240 Wood"). The slider's own
  ///    `240 / 240` beside a stock of 8 000 says the same thing in the place
  ///    you are already looking.
  Widget _tradeRow({
    required String resource,
    required String subtitle,
    required String sliderKey,
    required double max,
    required double amount,
    required String result,
    required String action,
    required String? blocked,
    required VoidCallback onTap,
  }) {
    final live = blocked == null && _busy == null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: Column(
        children: [
          Row(
            children: [
              Text(_emoji(resource), style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _name(resource),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FoE.label(size: 12).copyWith(color: _ink),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FoE.dim(size: 10).copyWith(color: _inkFaint),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // The price rides ON the commit, so the whole right-hand edge of
              // the list is a column of prices you can compare downward.
              _miniPill(
                live ? '$action  $result' : (blocked ?? action),
                live ? FoE.positive : _inkFaint,
                live ? onTap : null,
                filled: live,
              ),
            ],
          ),
          _amountSlider(sliderKey, max),
        ],
      ),
    );
  }

  // ── Tab 2: gold → items (the sink) ────────────────────────────────────
  List<Widget> _shopBody(double discount) {
    final stock = shopStock();
    final bag = _ctrl.items;
    return [
      _intro(
        "Buy what your Workshop hasn't made yet — over the counter, not on the "
        'road: an item you need for the fight you are in right now is worth '
        'nothing in two hours.',
      ),
      if (stock.isEmpty)
        Text(
          'Nothing is stocked yet — give an item a buy price in Dev Mode → '
          'Items.',
          style: FoE.dim(size: 11).copyWith(color: FoE.danger),
        )
      else
        // ONE LIST, NOT A STACK OF CARDS (user 2026-07-27: "der shop ist noch
        // sehr unübersichtlich, gib mir eine kompaktere übersichtlichere
        // darstellung").
        //
        // Every item had its own card: a name row, a description, a full-width
        // green Buy button carrying the price, and a ghost Sell pill under it —
        // about 150 px each, so six items were three screens and the prices,
        // the one thing you compare across a shop, never lined up in a column.
        //
        // The Healing Hut's shape instead: one framed list with hairlines, a
        // row per item at ~52 px. The price rides ON the Buy pill, which is
        // where it was going to be read anyway, so the whole right-hand edge is
        // a column of costs.
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: _cardFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kParchmentInk.withValues(alpha: 0.18)),
          ),
          child: Column(
            children: [
              for (var i = 0; i < stock.length; i++) ...[
                if (i > 0)
                  Container(
                    height: 1,
                    color: kParchmentInk.withValues(alpha: 0.13),
                  ),
                _shopRow(stock[i], bag[stock[i].id] ?? 0, discount),
              ],
            ],
          ),
        ),
    ];
  }

  /// One item: what it is, what it does, and the two moves — buy at the price
  /// on the pill, and sell one back when you hold any.
  ///
  /// The owned count sits ON the glyph as a stack badge rather than as a phrase
  /// ("in bag ×2") competing with the name: it is a fact about the picture, and
  /// at a glance a numbered stack reads faster than a sentence.
  Widget _shopRow(ItemDef def, int owned, double discount) {
    final key = 'shop_${def.id}';
    final cost = itemBuyCost(def, discount: discount);
    final back = itemSellValue(def, discount: discount);
    final busy = _busy == key;
    final affordable = _ctrl.gold >= cost;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Text(def.emoji, style: const TextStyle(fontSize: 19)),
                if (owned > 0)
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: _accent,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        '$owned',
                        style: FoE.value(size: 9).copyWith(
                          color: kParchmentLight,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  def.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FoE.label(size: 12).copyWith(color: _ink),
                ),
                const SizedBox(height: 2),
                Text(
                  def.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FoE.dim(size: 10).copyWith(color: _inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Selling back always pays less than buying (see itemSellValue), so
          // it stays the quiet ghost beside the commit — never a way to make
          // money, and never in front of the thing you came here to do.
          if (back > 0 && owned > 0) ...[
            _miniPill(
              '↩ $back',
              _accent,
              busy ? null : () => _run(key, () => _ctrl.sellItem(def.id)),
            ),
            const SizedBox(width: 6),
          ],
          _miniPill(
            '🪙 $cost',
            affordable ? FoE.positive : _inkFaint,
            busy || !affordable
                ? null
                : () => _run(key, () => _ctrl.buyItem(def.id)),
            filled: affordable,
          ),
        ],
      ),
    );
  }

  /// The compact control a shop row acts through: 28 px tall, tinted in its own
  /// colour, filled when it is the row's live commit. The Healing Hut's pill.
  Widget _miniPill(
    String label,
    Color color,
    VoidCallback? onTap, {
    bool filled = false,
  }) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Opacity(
      opacity: onTap == null ? 0.55 : 1,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: filled ? 0.9 : 0.07),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: color.withValues(alpha: filled ? 0.9 : 0.5)),
        ),
        child: Text(
          label,
          style: FoE.label(size: 11).copyWith(
            color: filled ? kParchmentLight : color,
          ),
        ),
      ),
    ),
  );

  // ── Tab 3: goods ↔ goods, and gold → goods ────────────────────────────
  List<Widget> _exchangeBody(
    List<String> tradeable,
    Map<String, double> stock,
    double discount,
  ) {
    // Keep the two pickers on resources this era actually knows.
    if (!tradeable.contains(_from)) _from = tradeable.first;
    if (!tradeable.contains(_to) || _to == _from) {
      _to = tradeable.firstWhere((r) => r != _from, orElse: () => _from);
    }
    final have = stock[_from] ?? 0;
    final fee = barterFee(discount);

    return [
      _intro(
        'Swap what you have for what a recipe wants. A barter keeps '
        '${((1 - fee) * 100).round()}% of the value; buying with gold costs '
        '${goodsBuyMarkup(discount).toStringAsFixed(1)}× what selling pays.',
      ),
      _barterCard(have, discount),
      const SizedBox(height: 4),
      Text(
        'Buy with gold',
        style: FoE.title(size: 13).copyWith(color: _ink),
      ),
      const SizedBox(height: 8),
      _tradeList([
        for (final r in tradeable) _buyGoodsRow(r, stock[r] ?? 0, discount),
      ]),
    ];
  }

  /// The barter, as one compact block: what you give and what you want as two
  /// pills, the amount under them, and the commit carrying the return.
  ///
  /// It stays a block rather than a row because — unlike selling — it is one
  /// CONFIGURABLE trade rather than one per resource: the two pickers are the
  /// whole point, and they need a line of their own.
  Widget _barterCard(double have, double discount) {
    const key = 'barter';
    final tradeable = tradeableResources(_ctrl.settlement?.eraIndex ?? 1);
    // Bounded by BOTH legs: what goes out and what comes back have to fit in
    // the same cargo hold.
    final maxIn = _caravan.isEmpty
        ? 0.0
        : maxBarterInput(
            from: _from,
            to: _to,
            available: have,
            yieldPerUnit:
                barterYield(_from, _to, 1000, discount: discount) / 1000,
            members: _caravan,
            carryMult: _ctrl.caravanBonuses.carryMult,
          );
    final amount = _amountFor(key, maxIn);
    final gain = barterYield(_from, _to, amount, discount: discount);
    final blocked = _blockedReason(_from, amount, gain > 0);
    final live = blocked == null && _busy == null;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      decoration: BoxDecoration(
        color: _cardFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kParchmentInk.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The era's goods as PILLS, not Material dropdowns (the shared
          // filter_pills look) — same control the egg picker's filters wear.
          Row(
            children: [
              Expanded(child: _goodsPill('Give', _from, tradeable, (v) {
                setState(() {
                  _from = v;
                  if (_to == _from) {
                    _to = tradeable.firstWhere((r) => r != _from,
                        orElse: () => _from);
                  }
                });
              })),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child:
                    Text('→', style: FoE.value(size: 13).copyWith(color: _accent)),
              ),
              Expanded(
                child: _goodsPill(
                  'Get',
                  _to,
                  tradeable.where((r) => r != _from).toList(),
                  (v) => setState(() => _to = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${have.toInt()} ${_name(_from)} in store',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FoE.dim(size: 10).copyWith(color: _inkFaint),
                ),
              ),
              const SizedBox(width: 8),
              _miniPill(
                live
                    ? 'Trade  ${gain.toInt()} ${_name(_to)}'
                    : (blocked ?? 'Trade'),
                live ? FoE.positive : _inkFaint,
                live
                    ? () => _run(
                        key,
                        () => _send(
                          from: _from,
                          amountFrom: amount,
                          to: _to,
                          amountTo: gain,
                        ),
                      )
                    : null,
                filled: live,
              ),
            ],
          ),
          _amountSlider(key, maxIn),
        ],
      ),
    );
  }

  Widget _buyGoodsRow(String resource, double stock, double discount) {
    final key = 'buy_$resource';
    // Buying runs the caravan the other way round: gold is the cargo going out,
    // the goods are what comes home — so the CAPACITY that binds is the one for
    // the goods, not for the gold.
    final cap = _capacity(resource);
    // THREE CEILINGS, and the slider stops at the lowest: what fits in the hold
    // on the way home, what the purse covers — and what fits in the hold on the
    // way OUT, because gold is cargo too.
    final affordable =
        goodsForGold(resource, _ctrl.gold.toInt(), discount: discount);
    final payable =
        goodsForGold(resource, _capacity('gold').floor(), discount: discount);
    final max =
        [cap, affordable, payable].reduce((a, b) => a < b ? a : b).floorToDouble();
    final n = _amountFor(key, max);
    final cost = goodsBuyCost(resource, n, discount: discount);

    return _tradeRow(
      resource: resource,
      subtitle: '${stock.toInt()} in store',
      sliderKey: key,
      max: max,
      amount: n,
      result: '🪙 $cost',
      action: 'Buy',
      blocked: _caravan.isEmpty
          ? 'Prepare a caravan'
          : affordable < 1
              ? 'Not enough gold'
              : cap < 1 || payable < 1
                  ? 'The caravan cannot haul this'
                  : n < 1
                      ? 'Nothing to buy'
                      : null,
      onTap: () => _run(
        key,
        () => _send(
          from: 'gold',
          amountFrom: cost.toDouble(),
          to: resource,
          amountTo: n.toDouble(),
        ),
      ),
    );
  }

  /// Why a goods send is off, in the order the player can fix it. Null when it
  /// is live — a greyed button that repeats its own label says it is off but
  /// not WHY, which is the Hatchery's rule for the same button.
  String? _blockedReason(String resource, double amount, bool pays) {
    if (_caravan.isEmpty) return 'Prepare a caravan';
    // The caravan pool, checked HERE rather than at send: a full pool is a
    // state you can see coming, and learning about it from a bounced trade
    // after picking a load is the thing this file keeps trying not to do.
    if (_exp.caravansFull) return 'Every caravan is out';
    if (amount <= 0) return 'Nothing to send';
    if (!pays) return 'Too little to be worth anything';
    return null;
  }

  // ── Small shared pieces ───────────────────────────────────────────────

  /// What a card is set to trade, in whole units, bounded by [max]. Unset means
  /// the whole load; a stored value that no longer fits is clamped rather than
  /// forgotten, so shrinking the caravan and growing it again gives your number
  /// back.
  double _amountFor(String key, double max) {
    if (max <= 0) return 0;
    return (_amount[key] ?? max).clamp(0, max).floorToDouble();
  }

  String _name(String resource) => resource == 'gold'
      ? 'gold'
      : kGoodsDefs[resource]?.name ?? _titleCase(resource);

  String _emoji(String resource) => resource == 'gold'
      ? '🪙'
      : resourceEmoji(resource);

  /// HOW MUCH — A SLIDER IN UNITS (user 2026-07-27: "mache einen slider und
  /// nicht in prozent sondern in effektiven zahlen").
  ///
  /// It was 25% / 50% / All. Percentages of WHAT was the problem: of the stock,
  /// of the caravan's hold, of whichever was smaller? All three read the same on
  /// the button, and none of them is the number a recipe asks you for — a recipe
  /// wants 40 planks, not half a caravan. The slider states the units outright
  /// and lands on any of them, and its ceiling is the real limit (stock and hold
  /// together, and the purse where gold is the cargo).
  ///
  /// The right-hand readout is `chosen / ceiling`, so the bound is on screen
  /// while you drag rather than discovered by hitting the end of the track.
  Widget _amountSlider(String key, double max, [String? unit]) {
    final live = max >= 1;
    final value = _amountFor(key, max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // The compact rows name the resource on their own first line, so
            // they pass no label and the readout alone rides above the track.
            if (unit != null)
              Text(unit, style: FoE.dim(size: 10).copyWith(color: _inkFaint)),
            const Spacer(),
            Text(
              live ? '${value.toInt()} / ${max.toInt()}' : '0',
              style: FoE.value(size: 12).copyWith(
                color: live ? _accent : _inkFaint,
              ),
            ),
          ],
        ),
        // FULL HEIGHT, NOT A 28 px BAND (user 2026-07-27: "der slider
        // funktioniert nicht"). It was wrapped in a SizedBox 28 tall with the
        // theme's own padding zeroed out — and a Slider's gesture area IS its
        // render box, so the whole control was a 28-pixel strip on a touch
        // screen, well under the 48 px minimum tap target. It worked under a
        // mouse and was near-impossible to grab with a thumb.
        //
        // Flutter's default sizing gives it the full interactive height; the
        // track still LOOKS thin because that is `trackHeight`, which is the
        // knob that should have been turned in the first place.
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 6,
            activeTrackColor: _accent,
            inactiveTrackColor: kParchmentInk.withValues(alpha: 0.13),
            disabledActiveTrackColor: kParchmentInk.withValues(alpha: 0.13),
            disabledInactiveTrackColor: kParchmentInk.withValues(alpha: 0.13),
            thumbColor: _accent,
            disabledThumbColor: _inkFaint,
            overlayColor: _accent.withValues(alpha: 0.12),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
          ),
          child: Slider(
            // A dead card still draws its track — greyed and unresponsive
            // rather than absent, so the cards keep the same height whether or
            // not a caravan is loaded.
            value: live ? value : 0,
            max: live ? max : 1,
            onChanged: live
                ? (v) => setState(() => _amount[key] = v.floorToDouble())
                : null,
          ),
        ),
      ],
    );
  }

  Widget _goodsPill(
    String label,
    String value,
    List<String> options,
    ValueChanged<String> onChanged,
  ) => MenuPill<String>(
    palette: _pills,
    icon: Icons.inventory_2_outlined,
    label: '${_emoji(value)} ${_name(value)}',
    // Never "engaged": both halves always hold a good, so an accent here would
    // be permanent and say nothing.
    engaged: false,
    value: value,
    entries: [
      for (final r in options) MapEntry(r, '${_emoji(r)} ${_name(r)}'),
    ],
    onSelected: onChanged,
  );

  static String _titleCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
