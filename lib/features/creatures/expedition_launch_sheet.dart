import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../../core/ui/feel.dart';
import '../settlement/settlement_controller.dart';
import '../settlement/widgets/parchment_sheet.dart';
import '../settlement/widgets/scroll_paper.dart'
    show kParchmentLight, parchmentButton;
import 'models/area.dart';
import 'models/expedition.dart' show ExpeditionType;
import 'models/creature_enums.dart';
import 'models/creature_instance.dart';
import 'models/species_def.dart';
import 'services/capture_math.dart';
import 'services/creatures_controller.dart';
import 'services/expedition_controller.dart';
import 'services/expedition_risk.dart';
import '../settlement/data/gather_defs.dart';
import 'services/expedition_targets.dart';
import 'services/gather_math.dart';
import 'widgets/creature_card.dart';
import '../common/widgets/parchment_kit.dart';
import '../common/widgets/recess_bar.dart';

/// Picks the group for [target] and sends the trip. Returns true when one was
/// actually dispatched.
///
/// A SHEET over the expeditions screen, not a page (user 2026-07-25): the trips
/// already out are the context for deciding who to send next — how many slots
/// are left, who is still away — so covering that list with a full screen threw
/// away the thing you were reading. It also merges the two old planner screens
/// (expedition_planner_screen / capture_planner_screen), which had drifted into
/// two different layouts for the same decision: pick a group, read the
/// forecast, send.
Future<bool?> showExpeditionLaunchSheet(
  BuildContext context,
  ExpeditionTarget target,
) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _LaunchSheet(target: target),
);

class _LaunchSheet extends StatefulWidget {
  final ExpeditionTarget target;
  const _LaunchSheet({required this.target});

  @override
  State<_LaunchSheet> createState() => _LaunchSheetState();
}

class _LaunchSheetState extends State<_LaunchSheet> {
  final _creatures = CreaturesController();
  final _expeditions = ExpeditionController();
  final _settlement = SettlementController();

  final Set<String> _selected = {};
  bool _sending = false;

  /// Hunt only: which variant (index into kCaptureHuntOptions). Each has a
  /// fixed duration and an EXACT hunter count.
  int _optionIndex = 0;

  AreaDef get _area => widget.target.area;
  bool get _isHunt => widget.target.isHunt;
  CaptureHuntOption get _option => kCaptureHuntOptions[_optionIndex];

  List<CreatureInstance> get _available => _creatures.availableForExpedition();
  List<CreatureInstance> get _members =>
      _available.where((c) => _selected.contains(c.id)).toList();

  /// Hunt: exactly the variant's hunter count. Gather: the party allowance.
  int get _groupCap => _isHunt ? _option.hunters : _creatures.teamSizeCap;

  GatherPlan? get _plan => widget.target.spot == null
      ? null
      : _expeditions.preview(
          area: _area,
          spot: widget.target.spot!,
          members: _members,
        );

  /// What a hunt here can find. EVERY species, minus the legendaries still
  /// standing (user 2026-07-27) — the area decides the danger, the level and
  /// the travel, no longer the guest list.
  List<SpeciesDef> get _pool =>
      catchableSpecies(_settlement.dungeonMaxStage);

  int get _unlockedOptions =>
      maxHuntOptionCount(_settlement.buildingHuntOptions);

  void _toggle(CreatureInstance c) {
    final selected = _selected.contains(c.id);
    if (!selected && _selected.length >= _groupCap) {
      // Hunts need an exact count, so silently swapping the oldest pick would
      // hide which monster left the group. Say what the limit is instead.
      _say(_isHunt
          ? 'The ${_option.label} hunt takes ${_option.hunters} '
              'hunter${_option.hunters > 1 ? 's' : ''} — deselect one, or pick '
              'a longer variant.'
          : 'You may send $_groupCap monster${_groupCap > 1 ? 's' : ''} — '
              'win battles to widen the party.');
      return;
    }
    setState(() => selected ? _selected.remove(c.id) : _selected.add(c.id));
  }

  void _selectOption(int i) {
    setState(() {
      _optionIndex = i;
      while (_selected.length > kCaptureHuntOptions[i].hunters) {
        _selected.remove(_selected.last);
      }
    });
  }

  void _say(String message) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, style: FoE.label(size: 12)),
      backgroundColor: kInk,
    ),
  );

  Future<void> _send() async {
    setState(() => _sending = true);
    final err = _isHunt
        ? await _expeditions.startCapture(
            area: _area,
            members: _members,
            option: _option,
          )
        : await _expeditions.startGather(
            area: _area,
            spot: widget.target.spot!,
            members: _members,
          );
    if (!mounted) return;
    setState(() => _sending = false);
    if (err != null) {
      Feel.deny();
      _say(err);
      return;
    }
    Feel.success();
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => ParchmentSheet(
    title: _isHunt ? 'Hunt' : 'Gather ${widget.target.label}',
    initialSize: 0.85,
    minSize: 0.5,
    maxSize: 0.95,
    trailing: Text(
      '${_expeditions.activeCount}/${_expeditions.maxSlots}',
      style: FoE.value(size: 13).copyWith(color: kAccent),
    ),
    builder: (context, scrollCtrl) => Column(
      children: [
        // WHERE, under the title — the region and its danger decide the level
        // of what lives there and how likely a casualty is, so they belong with
        // the heading rather than buried in the body.
        Padding(
          padding: const EdgeInsets.fromLTRB(26, 0, 26, 6),
          child: Row(
            children: [
              Text(widget.target.emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_area.emoji} ${_area.name} · Danger ${_area.dangerLevel}',
                  style: FoE.dim(size: 11)
                      .copyWith(color: ParchmentSheet.inkSoft),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(26, 4, 26, 14),
            children: _isHunt ? _huntBody() : _gatherBody(),
          ),
        ),
        _sendBar(),
      ],
    ),
  );

  // ── Gather ────────────────────────────────────────────────
  List<Widget> _gatherBody() {
    final spot = widget.target.spot!;
    final plan = _plan;
    final stock = _expeditions.availableStock(spot);
    // Capacity / regen / mining speed are per-RESOURCE dials now (Dev Mode →
    // Resources), not per spot.
    final dials = gatherDefFor(spot.resource);
    return [
      _panel([
        _kv('In the ground', '${stock.toStringAsFixed(0)} / '
            '${dials.spotCapacity.toStringAsFixed(0)}'),
        _bar(dials.spotCapacity <= 0 ? 0 : stock / dials.spotCapacity,
            kParchmentGo),
        const SizedBox(height: 8),
        _kv('Regrows', '${dials.regenPerHour.toStringAsFixed(0)}/h'),
        _kv('One carry point holds',
            '${_fmtNum(dials.unitsPerCarry)} ${spot.resource}'),
      ]),
      const SizedBox(height: 12),
      _panel([
        Text('This trip',
            style: FoE.label(size: 12).copyWith(color: kAccent)),
        const SizedBox(height: 8),
        _kv('Haul', plan == null || !plan.isViable
            ? '—'
            : '${plan.amount.toStringAsFixed(0)} ${plan.resource}'),
        _kv('Carry cap', plan?.loadCap.toStringAsFixed(0) ?? '0'),
        _kv('Mining rate', '${plan?.ratePerHour.toStringAsFixed(1) ?? '0'}/h'),
        _kv('Duration',
            plan != null && plan.isViable ? fmtTripDuration(plan.duration) : '—'),
        _kv('Risk', perilLabel(perilRatio(_area.dangerLevel, _members))),
      ]),
      const SizedBox(height: 14),
      ..._groupSection(
        hint: 'Mining speed is the group\'s gather stat; the load cap is its '
            'carry. A full load ends the trip.',
        // The two stats a miner is judged on, exactly where the caravan
        // picker puts its carry/speed pair.
        caption: (c) => '⛏️ ${gatherPowerOf(c)}   '
            '🎒 ${c.statValue(CreatureStat.carry)}',
      ),
    ];
  }

  // ── Hunt ──────────────────────────────────────────────────
  List<Widget> _huntBody() {
    final pool = _pool;
    if (pool.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'No species are defined yet.\nAdd some in '
            'Dev Mode → Species.',
            textAlign: TextAlign.center,
            style: FoE.dim(size: 12),
          ),
        ),
      ];
    }
    final present = pool.map((s) => s.rarity).toSet();

    // WHAT THE SHEET NO LONGER SHOWS (user 2026-07-30: "what lives here kann
    // komplett gelöscht werden. Catch timing kann gelöscht werden. Seltenheit
    // kann in ein kleines 'i' gepackt werden").
    //
    // Two full panels used to sit between the player and the only decision on
    // this sheet — which variant, and who goes. A roster of every catchable
    // species, and a per-rarity timing table. Neither changes with the choice;
    // both are reference. The rarity ODDS do move with the variant, so they
    // survive — one tap away, under the section whose selection changes them.
    return [
      ParchmentSectionHeader(
        title: 'Hunt length',
        trailing: ParchmentInfoButton(
          title: 'Find odds',
          content: (_) => _oddsRows(present),
        ),
      ),
      Text(
        'A longer hunt needs more hunters, brings back more finds and shifts '
        'the odds toward the rare end.',
        style: FoE.dim(size: 10).copyWith(color: kInkFaint),
      ),
      const SizedBox(height: 8),
      // THREE ACROSS (user 2026-07-30: "immer drei hunt optionen
      // nebeneinander"). Six full-width rows pushed the group picker off the
      // sheet entirely; as a grid the whole ladder is one glance.
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          mainAxisExtent: 92,
        ),
        itemCount: kCaptureHuntOptions.length,
        itemBuilder: (_, i) => _variantTile(i),
      ),
      const SizedBox(height: 14),
      ..._groupSection(
        hint: 'Every find is caught by hand when the group returns. Your best '
            'catcher widens the golden zone in that mini-game.',
        caption: (c) => '🪤 ${c.statValue(CreatureStat.catchRate)}',
      ),
    ];
  }

  /// The odds table, built when the ⓘ is opened so it reflects the variant
  /// chosen at that moment — a longer hunt biases the roll toward the rare end.
  List<Widget> _oddsRows(Set<CreatureRarity> present) {
    final weights = biasedRarityWeights(_area.dangerLevel, _option.rareBias);
    final total = present.fold<double>(0, (s, r) => s + (weights[r] ?? 0));
    return [
      Text(
        'What a ${_option.label} hunt in ${_area.name} turns up, and at which '
        'level. Rarer finds take more perfect hits to land.',
        style: FoE.dim(size: 11).copyWith(color: kInkSoft),
      ),
      const SizedBox(height: 10),
      _kv('Target level', 'Lv ${captureTargetLevel(_area)}'),
      const Divider(height: 16),
      for (final r in CreatureRarity.values)
        if (present.contains(r) && total > 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Text(r.label,
                    style: FoE.label(size: 12).copyWith(color: r.color)),
                const Spacer(),
                Text(
                  '${qteHitsRequired(r)} hit'
                  '${qteHitsRequired(r) > 1 ? 's' : ''}',
                  style: FoE.dim(size: 11).copyWith(color: kInkFaint),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${((weights[r] ?? 0) / total * 100).round()} %',
                    textAlign: TextAlign.end,
                    style: FoE.value(size: 12).copyWith(color: kInk),
                  ),
                ),
              ],
            ),
          ),
      const Divider(height: 16),
      _kv('Risk', perilLabel(perilRatio(_area.dangerLevel, _members))),
    ];
  }

  /// One hunt length, as a CARD rather than a row — three fit across.
  ///
  /// What survived the squeeze is what the choice is actually made on: how
  /// long, how many hunters, how many finds. The lock reason moved to the tap,
  /// because a grid cell has no room for a sentence and the sentence is only
  /// needed once.
  Widget _variantTile(int i) {
    final o = kCaptureHuntOptions[i];
    final availableCount = _available.length;
    final lockedByProgress = i >= _unlockedOptions;
    final lockedByCount = availableCount < o.hunters;
    final locked = lockedByProgress || lockedByCount;
    final active = _optionIndex == i;
    return GestureDetector(
      onTap: () {
        if (!locked) {
          _selectOption(i);
        } else if (lockedByProgress) {
          _say('Win more battles to unlock the ${o.label} hunt.');
        } else {
          _say('The ${o.label} hunt needs ${o.hunters} ready monsters — '
              'you have $availableCount.');
        }
      },
      child: Opacity(
        opacity: locked ? 0.5 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: ShapeDecoration(color: active
                ? kAccent.withValues(alpha: 0.12)
                : kInk.withValues(alpha: 0.06), shape: FoE.facet(radius: 10, side: BorderSide(color: active
                  ? kAccent.withValues(alpha: 0.55)
                  : kInk.withValues(alpha: 0.18),
              width: active ? 1.6 : 1))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${locked ? '🔒 ' : ''}${o.label}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FoE.title(size: 13)
                    .copyWith(color: active ? kAccent : kInk),
              ),
              const SizedBox(height: 3),
              Text(
                '🪤 ${o.finds} find${o.finds > 1 ? 's' : ''}',
                style: FoE.label(size: 11).copyWith(color: kInkSoft),
              ),
              Text(
                // The hunter count is only worth a line when a variant wants
                // more than the usual one — six copies of "🐾 1" is noise.
                [
                  if (o.hunters > 1) '🐾 ${o.hunters}',
                  if (o.rareBias > 0) '✨ +${(o.rareBias * 100).round()}%',
                ].join('  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FoE.dim(size: 10).copyWith(color: kInkFaint),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Group picker (shared) ─────────────────────────────────
  // PLACES, NOT A ROSTER (user 2026-07-30: "Unten nicht alle monster, sondern
  // diese Buttons entsprechend der möglichen Monsterzahl").
  //
  // It listed every free monster, which on a full collection is a wall of tiles
  // between the player and the Send button — and it never showed the one number
  // that decides the trip: how many may go. Now the sheet shows exactly that
  // many PLACES, the way the Market shows a caravan's, and filling one opens the
  // roster. Same frame as the Hatchery's egg slot and the breeding screen's
  // parents, so an empty place lines up with the tile that will fill it.
  //
  // Shared by hunt and gather: both ask "who goes", only the cap and the
  // caption differ.
  static const double _kTileAspect = 0.70;

  List<Widget> _groupSection({
    required String hint,
    required String Function(CreatureInstance) caption,
  }) => [
    ParchmentSectionHeader(
      title: 'Group',
      hint: '${_members.length} / $_groupCap chosen',
    ),
    Text(hint, style: FoE.dim(size: 10).copyWith(color: kInkFaint)),
    // "THE SAME AGAIN" (user 2026-07-30). Sending a party is the most repeated
    // action in the game, and it was a fresh hunt through the roster every time.
    // Only shown when it would actually DO something: there is a remembered
    // party, somebody in it is still free, and they are not already picked.
    if (_lastPartyAvailable().isNotEmpty) ...[
      const SizedBox(height: 8),
      _sameAgainButton(),
    ],
    const SizedBox(height: 10),
    GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: _kTileAspect,
      ),
      itemCount: _groupCap,
      itemBuilder: (_, i) {
        final chosen = _members;
        return i < chosen.length
            ? _filledPlace(chosen[i])
            : _emptyPlace(isNext: i == chosen.length);
      },
    ),
  ];

  /// A place waiting to be filled. A tap opens the roster.
  ///
  /// Only the NEXT one to be filled says "Add" — six copies of the word is
  /// noise, and one is a caption for the whole rank.
  Widget _emptyPlace({required bool isNext}) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: _openPicker,
    child: LayoutBuilder(
      // The tile reserves its top 17 % for the art that pops out of it; the
      // empty card leaves the same gap so the row lines up.
      builder: (context, box) => Padding(
        padding: EdgeInsets.only(top: box.maxHeight * 0.17),
        child: Container(
          decoration: ShapeDecoration(color: kInk.withValues(alpha: 0.10),
            
            shadows: [
              BoxShadow(
                color: kInk.withValues(alpha: 0.24),
                blurRadius: 0,
                offset: const Offset(0, 3),
              ),
            ], shape: FoE.facet(radius: 22)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_circle_outline, size: 24, color: kInkFaint),
              if (isNext) ...[
                const SizedBox(height: 5),
                Text('Add',
                    style: FoE.label(size: 11).copyWith(color: kInkFaint)),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  /// A filled place: THE monster tile, unchanged from every other screen.
  ///
  /// A TAP TAKES IT BACK OUT. Emptying a place is the exact inverse of filling
  /// it, so it is the same single tap on the same place — no picker, and no
  /// rebuilding the group to drop one member.
  Widget _filledPlace(CreatureInstance c) => Stack(
    children: [
      Positioned.fill(
        child: CreatureCard(creature: c, onTap: () => _toggle(c)),
      ),
      Positioned(
        top: 2,
        right: 2,
        child: IgnorePointer(
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: kInk.withValues(alpha: 0.55),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.close, size: 12, color: Colors.white),
          ),
        ),
      ),
    ],
  );

  /// The roster, as a sheet over this one — opened only while a place is being
  /// filled, which is what keeps it off the page the rest of the time.

  /// The remembered party, minus whoever cannot go now (K.O., stationed away,
  /// breeding, already out) and minus anyone already picked — capped at the
  /// group size. Empty when the shortcut would change nothing.
  List<CreatureInstance> _lastPartyAvailable() {
    final ids = _expeditions.lastParty[
      _isHunt ? ExpeditionType.capture : ExpeditionType.gather
    ];
    if (ids == null) return const [];
    final free = {for (final c in _available) c.id: c};
    final out = <CreatureInstance>[];
    for (final id in ids) {
      final c = free[id];
      if (c == null || _selected.contains(id)) continue;
      if (out.length + _selected.length >= _groupCap) break;
      out.add(c);
    }
    return out;
  }

  Widget _sameAgainButton() {
    final party = _lastPartyAvailable();
    final missing = (_expeditions.lastParty[
              _isHunt ? ExpeditionType.capture : ExpeditionType.gather
            ]?.length ??
            0) -
        party.length -
        _selected.length;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Feel.tap();
        setState(() {
          for (final c in party) {
            _selected.add(c.id);
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: parchmentButton(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.replay_rounded, size: 14, color: kInk),
            const SizedBox(width: 6),
            Text(
              'Same as last time (${party.length})',
              style: FoE.label(size: 11).copyWith(color: kInk),
            ),
            // Honest about what it CANNOT bring back — silently sending a
            // smaller party than the one you remember is the worse failure.
            if (missing > 0) ...[
              const SizedBox(width: 6),
              Text(
                '· $missing busy',
                style: FoE.dim(size: 10).copyWith(color: kInkFaint),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openPicker() async {
    if (_available.isEmpty) {
      _say('Nobody is free — everyone is K.O., stationed, breeding or out.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ParchmentSheet(
        title: 'Who goes?',
        initialSize: 0.7,
        builder: (sheetCtx, scrollCtrl) => StatefulBuilder(
          // Its own builder so a pick repaints the picker; the places behind it
          // catch up when it closes.
          builder: (sheetCtx, setSheetState) => GridView.builder(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(26, 4, 26, 20),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              mainAxisExtent: 152,
            ),
            itemCount: _available.length,
            itemBuilder: (_, i) => _pickerTile(
              _available[i],
              sheetCtx,
              setSheetState,
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _pickerTile(
    CreatureInstance c,
    BuildContext sheetCtx,
    void Function(VoidCallback) setSheetState,
  ) {
    final picked = _selected.contains(c.id);
    final caption = _isHunt
        ? '🪤 ${c.statValue(CreatureStat.catchRate)}'
        : '⛏️ ${gatherPowerOf(c)}   🎒 ${c.statValue(CreatureStat.carry)}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: picked ? 0.45 : 1,
                  child: CreatureCard(
                    creature: c,
                    onTap: () {
                      _toggle(c);
                      setSheetState(() {});
                      // A full group means the question is answered; holding
                      // the picker open would leave a list that refuses every
                      // further tap.
                      if (_members.length >= _groupCap) {
                        Navigator.pop(sheetCtx);
                      }
                    },
                  ),
                ),
              ),
              if (picked)
                const Positioned(
                  top: 2,
                  left: 2,
                  child:
                      Icon(Icons.check_circle, size: 18, color: kAccent),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 17,
          child: Center(
            child: Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FoE.dim(size: 10).copyWith(color: kInkSoft),
            ),
          ),
        ),
      ],
    );
  }

  // ── Send ──────────────────────────────────────────────────
  Widget _sendBar() {
    final full = _expeditions.slotsFull;
    final plan = _plan;
    final ready = _isHunt
        ? _members.length == _option.hunters
        : _members.isNotEmpty && plan != null && plan.isViable;
    final canSend = !_sending && !full && ready;

    final label = full
        // Zero slots is not a queue — name the building that opens them
        // instead of a busy party that isn't there (user 2026-07-29).
        ? _expeditions.noSlots
            ? 'No expedition slots — build a Scout Post'
            : 'All expedition slots busy '
                '(${_expeditions.activeCount}/${_expeditions.maxSlots})'
        : _isHunt
            ? ready
                ? 'Send ${_option.label} hunt · '
                    '${fmtTripDuration(captureDuration(_option))}'
                : 'Pick ${_option.hunters} hunter'
                    '${_option.hunters > 1 ? 's' : ''} '
                    '(${_members.length} chosen)'
            : ready
                ? 'Send expedition · ${fmtTripDuration(plan!.duration)}'
                : _members.isEmpty
                    ? 'Pick who goes'
                    : 'Nothing left to mine here';

    // The send bar is a FOOTER cut from the same paper, not a dark strip
    // bolted under the sheet (user 2026-07-29 redraw). A hairline above it is
    // what separates it from the scrolling list; the shadow does the rest.
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: kParchmentLight,
        border: Border(
          top: BorderSide(color: kInk.withValues(alpha: 0.18)),
        ),
        boxShadow: [
          BoxShadow(
            color: kInk.withValues(alpha: 0.16),
            blurRadius: 0,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        10,
        20,
        10 + MediaQuery.of(context).viewPadding.bottom,
      ),
      child: _sending
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: kAccent),
                ),
              ),
            )
          : ParchmentButton(
              label: label,
              expand: true,
              primary: canSend,
              onTap: canSend ? _send : null,
            ),
    );
  }

  // ── Small shared pieces ───────────────────────────────────
  Widget _panel(List<Widget> children) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: ParchmentSheet.card,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );

  Widget _kv(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Text(label, style: FoE.dim(size: 11).copyWith(color: kInkFaint)),
        const Spacer(),
        Text(value, style: FoE.value(size: 12).copyWith(color: kInk)),
      ],
    ),
  );

  Widget _bar(double fraction, Color color) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: RecessBar(
      value: fraction.clamp(0.0, 1.0),
      color: color,
      height: 9,
    ),
  );

  /// 20 → "20", 0.5 → "0.5" — carry weights are not always whole.
  static String _fmtNum(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

}

/// Trip lengths read as "1h 20m" / "12m" / "45s" everywhere they appear — the
/// planner sheet and the running-trip cards shared two near-identical copies of
/// this before.
String fmtTripDuration(Duration d) {
  if (d.inSeconds <= 0) return 'instant';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}
