import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/guild/guild_boss.dart';

void main() {
  test('the week picks the same boss on every device, and a level that grows', () {
    final a = GuildBoss.pick(3, now: DateTime.utc(2026, 11, 16, 8));
    final b = GuildBoss.pick(3, now: DateTime.utc(2026, 11, 20, 23));
    expect(a.species, b.species); // same week
    expect(a.level, 20);
    expect(GuildBoss.pick(10).level, 48);
    expect(GuildBoss.pick(99).level, 48); // capped like the level table
  });
}
