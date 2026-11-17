import 'package:flutter/material.dart' hide Text;

import '../../../core/theme/cream_kit.dart';
import '../../../core/theme/voxel_icons.dart';
import '../../../core/ui/pressable.dart';
import '../../../core/ui/scroll_cue.dart';
import '../../settlement/widgets/building_icon.dart';
import '../../common/widgets/parchment_page.dart' show ParchmentDialog;
import '../../social/widgets/social_kit.dart';
import '../models/combatant.dart';
import '../services/battle_rewards.dart';
import '../services/battle_stars.dart' show kStarHpFraction;
import '../services/overworld_layout.dart' show OverworldNodeState;
import 'enemy_card.dart';
import 'star_row.dart';
import '../../../core/ui/game_text.dart';

/// The share of HP for the third star, as the percentage the view prints.
final int _hpNeed = (kStarHpFraction * 100).round();

/// THE CAMPAIGN'S FOCUS VIEW (user 2026-11-03, concept 5 of 10: "Nächster
/// Kampf im Fokus"). The battle you have picked fills the screen under the
/// battle strip: on the left what it is and what it pays (title, stars, the
/// star rules, the reward), on the right WHO you face, big, and the one
/// button — with arrows to step to the battle before or after.
class OverworldFocusView extends StatelessWidget {
  final int battleNumber;
  final bool isBoss;
  final OverworldNodeState state;

  /// The foes the fight will field — null while the area has none authored.
  final List<Combatant>? enemies;

  /// What clearing it grants. Only the CURRENT battle grants anything (a
  /// re-fight is XP only), so the screen passes an empty list for the others.
  final List<RewardLine> rewards;

  /// Null = the button is off.
  final VoidCallback? onFight;

  /// The best stars earned here (0–3).
  final int stars;

  /// No battle-ready monster at all — the button says so instead of doing
  /// nothing (see OverworldFightCard.noTeam).
  final bool noTeam;

  /// Step to the battle before / after; null = there is none.
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  const OverworldFocusView({
    super.key,
    required this.battleNumber,
    required this.isBoss,
    required this.state,
    required this.enemies,
    required this.rewards,
    required this.onFight,
    this.stars = 0,
    this.noTeam = false,
    this.onPrev,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final locked = state == OverworldNodeState.locked;
    final done = state == OverworldNodeState.done;
    final blocked = locked || noTeam;
    final label = locked
        ? 'Win battle ${battleNumber - 1} first'
        : noTeam
        ? 'Catch a monster first'
        : done
        ? 'Fight again'
        : 'Fight';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 300, child: _info(locked, done)),
        const SizedBox(width: 10),
        _arrow(Icons.chevron_left_rounded, 'Previous battle', onPrev),
        const SizedBox(width: 8),
        Expanded(
          child: creamCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _heading('Enemies'),
                Expanded(
                  child: Center(
                    child: enemies == null || enemies!.isEmpty
                        ? Text(
                            'Nobody lives here yet.',
                            style: TextStyle(fontSize: 15, color: kBoxInkSoft),
                          )
                        : _BigEnemies(enemies!),
                  ),
                ),
                Center(
                  child: SizedBox(
                    width: 320,
                    child: SocialGoldButton(
                      label,
                      height: 54,
                      fontSize: 20,
                      onTap: blocked ? null : onFight,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        _arrow(Icons.chevron_right_rounded, 'Next battle', onNext),
      ],
    );
  }

  Widget _info(bool locked, bool done) => creamCard(
    padding: const EdgeInsets.fromLTRB(15, 12, 15, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isBoss ? 'Boss $battleNumber' : 'Battle $battleNumber',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w400,
            color: kBoxInk,
          ),
        ),
        if (!locked) ...[
          const SizedBox(height: 2),
          Row(
            children: [
              StarRow(count: stars, size: 22),
              const SizedBox(width: 8),
              // The three stars' rules (battle_stars.dart) live behind a small
              // "i" (user 2026-11-15) — the card's room goes to the rewards.
              Builder(
                builder: (context) => Semantics(
                  label: 'How stars are earned',
                  button: true,
                  child: Pressable(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => showDialog<void>(
                      context: context,
                      barrierColor: CreamPalette.dim,
                      builder: (_) => ParchmentDialog(
                        title: 'Stars',
                        closeLabel: 'Got it',
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                          child: Text(
                            '★  win the battle\n'
                            '★★  no monster knocked out\n'
                            '★★★  team keeps $_hpNeed % of its HP',
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.5,
                              color: kBoxInk,
                            ),
                          ),
                        ),
                      ),
                    ),
                    child: Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: kBoxInkSoft, width: 1.5),
                      ),
                      child: Text(
                        'i',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: kBoxInkSoft,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        _heading('Reward'),
        const SizedBox(height: 2),
        Expanded(
          child: rewards.isEmpty
              ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    done
                        ? 'Nothing new here — XP for your team, more for '
                              'more stars.'
                        : 'XP for your team.',
                    style: TextStyle(fontSize: 14, color: kBoxInkSoft),
                  ),
                )
              : ScrollCue(
                  builder: (context, controller) => ListView(
                    controller: controller,
                    padding: EdgeInsets.zero,
                    children: [for (final r in rewards) _RewardRow(r)],
                  ),
                ),
        ),
      ],
    ),
  );

  Widget _heading(String t) => Row(
    children: [
      Text(
        t.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          letterSpacing: 1.1,
          color: kBoxAccent,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Container(
          height: 1,
          color: CreamPalette.tan.withValues(alpha: 0.55),
        ),
      ),
    ],
  );

  Widget _arrow(IconData icon, String label, VoidCallback? onTap) => Center(
    child: Semantics(
      label: label,
      button: true,
      child: Pressable(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.3 : 1,
          child: Container(
            width: 40,
            height: 72,
            decoration: voxelBlock(),
            child: PixelIcon(icon, size: 28, color: kBoxInk),
          ),
        ),
      ),
    ),
  );
}

/// The foes as trading cards (user 2026-11-15), side by side as big as the
/// room allows — the card's own proportions, shrunk to fit when there are many.
class _BigEnemies extends StatelessWidget {
  final List<Combatant> enemies;
  const _BigEnemies(this.enemies);

  static const double _aspect = 0.7; // width / height
  static const double _gap = 14;

  @override
  Widget build(BuildContext context) {
    final n = enemies.length;
    return LayoutBuilder(
      builder: (context, box) {
        // The card keeps the library's proportions.
        var h = (box.maxHeight.isFinite ? box.maxHeight : 190.0);
        h = h.clamp(60.0, 200.0);
        var w = h * _aspect;
        final room = box.maxWidth - (n - 1) * _gap;
        if (n * w > room) {
          w = room / n;
          h = w / _aspect;
        }
        return SizedBox(
          height: h,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < n; i++) ...[
                if (i > 0) const SizedBox(width: _gap),
                SizedBox(width: w, height: h, child: EnemyCard(enemies[i])),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// One reward line — a new building with its own picture, anything else with
/// its emoji (the same look as the battle preparation).
class _RewardRow extends StatelessWidget {
  final RewardLine r;
  const _RewardRow(this.r);

  @override
  Widget build(BuildContext context) {
    final building = r.buildingId != null;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Center(
              child: building
                  ? BuildingIcon(defId: r.buildingId, emoji: r.emoji, size: 32)
                  : Text(r.emoji, style: const TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              building ? r.text.replaceFirst('New building: ', '') : r.text,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: kBoxInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
