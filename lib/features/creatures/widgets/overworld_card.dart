import 'package:flutter/material.dart' hide Text;

import '../../../core/theme/cream_kit.dart';
import '../../../core/ui/scroll_cue.dart';
import '../../settlement/widgets/building_icon.dart';
import '../../social/widgets/social_kit.dart';
import '../models/combatant.dart';
import '../services/battle_rewards.dart';
import '../services/battle_stars.dart' show kStarHpFraction;
import '../services/overworld_layout.dart' show OverworldNodeState;
import 'creature_family.dart' show CreatureAvatar, CreatureFace;
import 'star_row.dart';
import '../../../core/ui/game_text.dart';

/// The share of HP for the third star, as the percentage the card prints.
final int _hpNeed = (kStarHpFraction * 100).round();

/// THE OVERWORLD'S FIGHT CARD (user 2026-09-20, "Variante 4" — and "ich will nur
/// die wichtigen Informationen: Belohnung und Gegner").
///
/// A cream card beside the map that says only two things about the battle you
/// have picked: WHO you will face and WHAT you win — plus the one button that
/// goes on to the battle preparation. No region progress, no boss teaser, no
/// party rules: the map is the campaign, this is the fight in front of you.
class OverworldFightCard extends StatelessWidget {
  final int battleNumber;
  final bool isBoss;
  final OverworldNodeState state;

  /// The foes the fight will field — null while the area has none authored.
  final List<Combatant>? enemies;

  /// What clearing it grants. Only the CURRENT battle grants anything (a
  /// re-fight is XP only), so the map passes an empty list for the others.
  final List<RewardLine> rewards;

  /// Null = the button is off (locked battle).
  final VoidCallback? onFight;

  /// The best stars earned here (0–3) — the fight is judged for them every time
  /// (see battle_stars.dart), so they are shown before it starts.
  final int stars;

  /// True when the player has no battle-ready monster at all (reachable by
  /// skipping the guided intro on its very first card, before ever picking a
  /// starter). [onFight]'s own guard already no-ops the tap in that case, but
  /// silently — app policy killed every popup message (see [SnackX]), so a
  /// button that just does nothing has no way left to say why. Reusing the
  /// same grey/disabled treatment [locked] gets, with its own label, keeps
  /// that explanation on the card instead (user 2026-09-30 QA pass).
  final bool noTeam;

  const OverworldFightCard({
    super.key,
    required this.battleNumber,
    required this.isBoss,
    required this.state,
    required this.enemies,
    required this.rewards,
    required this.onFight,
    this.stars = 0,
    this.noTeam = false,
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
    return creamCard(
      padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            (locked
                    ? 'Locked'
                    : done
                    ? 'Cleared'
                    : 'Next fight')
                .toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w400,
              letterSpacing: 1.1,
              color: kBoxAccent,
            ),
          ),
          const SizedBox(height: 1),
          Row(
            children: [
              Expanded(
                child: Text(
                  isBoss
                      ? '👑 Boss battle $battleNumber'
                      : 'Battle $battleNumber',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w400,
                    color: kBoxInk,
                  ),
                ),
              ),
              // The best result so far — for a battle you can still take.
              if (!locked) StarRow(count: stars, size: 18),
            ],
          ),
          const SizedBox(height: 12),
          _heading('Enemies'),
          const SizedBox(height: 8),
          if (enemies == null || enemies!.isEmpty)
            Text(
              'Nobody lives here yet.',
              style: TextStyle(fontSize: 12, color: kBoxInkSoft),
            )
          else
            _EnemyRow(enemies!),
          const SizedBox(height: 14),
          _heading('Reward'),
          const SizedBox(height: 4),
          Expanded(
            child: rewards.isEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      // The stars decide how much (user 2026-09-28).
                      locked
                          ? 'XP for your team.'
                          : '${done ? 'Nothing new here — but a ' : 'A '}'
                                'better result earns more XP.\n'
                                '★★ no monster knocked out · '
                                '★★★ team keeps $_hpNeed % HP',
                      style: TextStyle(fontSize: 12, color: kBoxInkSoft),
                    ),
                  )
                : ScrollCue(
                    // A list longer than the card says so (user 2026-09-22).
                    builder: (context, controller) => ListView(
                      controller: controller,
                      padding: EdgeInsets.zero,
                      children: [for (final r in rewards) _RewardRow(r)],
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          SocialGoldButton(
            label,
            height: 42,
            fontSize: 14,
            onTap: blocked ? null : onFight,
          ),
          const SizedBox(height: 3),
        ],
      ),
    );
  }

  Widget _heading(String t) => Row(
    children: [
      Text(
        t.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
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
}

/// The foes, side by side — up to [kSideBySide] of them. More than that would
/// wrap onto a second row and push the reward off the card (user 2026-09-20:
/// "wenn es mehr als 3 Enemies sind, dann sehe ich die Rewards nicht mehr —
/// daher die Enemies stapeln"), so a crowd is STACKED instead: the faces overlap
/// in ONE row, each later one over the one before, with only its level under it.
class _EnemyRow extends StatelessWidget {
  final List<Combatant> enemies;
  const _EnemyRow(this.enemies);

  static const int kSideBySide = 3;

  /// The face's diameter, and the height of one row of faces with a label.
  static const double _face = 46;
  static const double _stackH = _face + 5 + 14;

  @override
  Widget build(BuildContext context) {
    if (enemies.length <= kSideBySide) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [for (final e in enemies) _EnemyFace(e)],
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        final n = enemies.length;
        // As spread out as the card allows, never further than a face and a
        // little air, and never so tight that a face vanishes under its
        // neighbour.
        final step = ((box.maxWidth - _face) / (n - 1)).clamp(
          _face * 0.45,
          _face + 6,
        );
        return SizedBox(
          height: _stackH,
          width: _face + (n - 1) * step,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < n; i++)
                Positioned(
                  left: i * step,
                  top: 0,
                  width: _face,
                  child: Tooltip(
                    message: '${enemies[i].name} · Lv ${enemies[i].level}',
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _EnemyBubble(enemies[i]),
                        const SizedBox(height: 5),
                        Text(
                          'Lv ${enemies[i].level}',
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                            color: kBoxInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// One foe: its face in its element's colour, level under it, name under that.
class _EnemyFace extends StatelessWidget {
  final Combatant e;
  const _EnemyFace(this.e);

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 64,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _EnemyBubble(e),
        const SizedBox(height: 5),
        Text(
          'Lv ${e.level}',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: kBoxInk,
          ),
        ),
        Text(
          e.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 10, color: kBoxInkSoft),
        ),
      ],
    ),
  );
}

/// The face itself â€” the monster family's small tile (user 2026-09-20), so an
/// enemy looks like the same monster does everywhere else; both layouts share it.
class _EnemyBubble extends StatelessWidget {
  final Combatant e;
  const _EnemyBubble(this.e);

  @override
  Widget build(BuildContext context) =>
      CreatureAvatar(CreatureFace.combatant(e), size: 46);
}

/// One reward line. A new building shows its own picture and name, like the
/// battle preparation does; everything else is its emoji and text.
class _RewardRow extends StatelessWidget {
  final RewardLine r;
  const _RewardRow(this.r);

  @override
  Widget build(BuildContext context) {
    final building = r.buildingId != null;
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Center(
              child: building
                  ? BuildingIcon(defId: r.buildingId, emoji: r.emoji, size: 28)
                  : Text(r.emoji, style: const TextStyle(fontSize: 18)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              building ? r.text.replaceFirst('New building: ', '') : r.text,
              style: const TextStyle(
                fontSize: 13,
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
