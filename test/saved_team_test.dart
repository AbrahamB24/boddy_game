import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/creatures/models/saved_team.dart';
import 'package:boddygame/features/creatures/services/creatures_controller.dart';

// battleTeam() is THE team rule — dungeon entry, the fight ladder, training and
// the tech trials all read it. These lock in what an active team means, because
// getting it wrong means the player walks into a boss with the wrong monsters
// and can't tell why.

CreatureInstance _mob(String id) => CreatureInstance(
  id: id,
  userId: 'u',
  speciesId: 's',
  gender: CreatureGender.male,
  statBase: const {CreatureStat.hp: 50},
  statSlope: const {},
);

SavedTeam _team(List<String> members, {bool active = true}) => SavedTeam(
  id: 't1',
  userId: 'u',
  name: 'Steinteam',
  memberIds: members,
  isActive: active,
);

void main() {
  final ctrl = CreaturesController();

  setUp(() {
    ctrl.creatures
      ..clear()
      ..addAll(['a', 'b', 'c', 'd'].map(_mob));
    ctrl.savedTeams.clear();
    ctrl.expeditionIds.clear();
    ctrl.breedingIds.clear();
  });

  test('with no team, the roster is catch order — the old behaviour', () {
    // Kept deliberately: a fresh profile has no teams. It's also exactly why
    // saved teams exist, since catch order means your OLDEST monsters.
    expect(ctrl.battleTeam(size: 2).map((c) => c.id), ['a', 'b']);
  });

  test('an active team decides who fights, in ITS order', () {
    ctrl.savedTeams.add(_team(['d', 'b']));
    expect(ctrl.battleTeam(size: 3).map((c) => c.id), ['d', 'b']);
  });

  test('an INACTIVE team changes nothing', () {
    ctrl.savedTeams.add(_team(['d', 'c'], active: false));
    expect(ctrl.battleTeam(size: 2).map((c) => c.id), ['a', 'b']);
  });

  test('the size cap trims from the end of the player order', () {
    ctrl.savedTeams.add(_team(['d', 'c', 'b']));
    expect(ctrl.battleTeam(size: 2).map((c) => c.id), ['d', 'c']);
  });

  test('unavailable members are skipped, not replaced', () {
    // The load-bearing one. Substituting a free monster for a K.O. member
    // would send someone the player never picked into a boss fight.
    ctrl.expeditionIds.add('d');
    ctrl.savedTeams.add(_team(['d', 'b']));
    expect(ctrl.battleTeam(size: 3).map((c) => c.id), ['b']);
  });

  test('a fully unavailable team yields nobody rather than falling back', () {
    // Callers check for an empty team and say "nobody can fight" — far better
    // than silently fielding the reserves.
    ctrl.breedingIds.addAll(['d', 'b']);
    ctrl.savedTeams.add(_team(['d', 'b']));
    expect(ctrl.battleTeam(size: 3), isEmpty);
  });

  test('a member that no longer exists is ignored', () {
    ctrl.savedTeams.add(_team(['ghost', 'a']));
    expect(ctrl.battleTeam(size: 3).map((c) => c.id), ['a']);
  });

  test('activeTeam finds the flagged one', () {
    ctrl.savedTeams
      ..add(_team(['a'], active: false))
      ..add(SavedTeam(id: 't2', userId: 'u', name: 'B', memberIds: ['b'],
          isActive: true));
    expect(ctrl.activeTeam?.name, 'B');
  });

  // ── Caravans share the table (migration 0028) ──────────────────────────
  // The Market's saved hauling parties live in `saved_teams` under a kind. They
  // must be invisible to everything that reads a FIGHTING roster, or saving a
  // caravan would silently change who walks into the next boss.

  group('a caravan is not a battle team', () {
    SavedTeam caravan(List<String> members, {bool active = false}) => SavedTeam(
      id: 'c1',
      userId: 'u',
      name: 'Ore run',
      kind: TeamKind.caravan,
      memberIds: members,
      isActive: active,
    );

    test('battleTeams lists only fighting rosters, caravans only caravans', () {
      ctrl.savedTeams
        ..add(_team(['a'], active: false))
        ..add(caravan(['c', 'd']));
      expect(ctrl.battleTeams.map((t) => t.name), ['Steinteam']);
      expect(ctrl.caravans.map((t) => t.name), ['Ore run']);
    });

    test('a caravan never becomes the active team', () {
      // Belt and braces: saveCaravan never sets the flag, but a row written by
      // hand (or a future bug) must not be able to hijack battleTeam() either.
      ctrl.savedTeams.add(caravan(['c', 'd'], active: true));
      expect(ctrl.activeTeam, isNull);
      expect(ctrl.battleTeam(size: 2).map((c) => c.id), ['a', 'b']);
    });

    test('a pre-0028 row has no kind and counts as a battle team', () {
      final row = SavedTeam.fromRow({
        'id': 't9',
        'user_id': 'u',
        'name': 'Legacy',
        'member_ids': ['d'],
        'is_active': true,
      });
      expect(row.kind, TeamKind.battle);
      ctrl.savedTeams.add(row);
      expect(ctrl.battleTeam(size: 2).map((c) => c.id), ['d']);
    });
  });
}
